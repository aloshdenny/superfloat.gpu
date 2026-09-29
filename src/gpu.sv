`default_nettype none
`timescale 1ns/1ns

// GPU - ATREIDES NEURAL NETWORK ACCELERATOR (OpenFrame build)
// > Built to use an external async memory with multi-channel read/write
// > Assumes that the program is loaded into program memory, data into data memory, and threads into
//   the device control register before the start signal is triggered
// > NUM_CORES core tiles. Each tile holds one core (THREADS_PER_BLOCK threads + one
//   SYSTOLIC_SIZE x SYSTOLIC_SIZE array), its decoder, a private 128B scratchpad at
//   0xFFC0..0xFFFF, and an arbiter that merges its LSUs into one data channel
// > The tile is the hardened macro; this level only dispatches blocks and routes channels
// > A shared instruction cache serves all tiles' fetches through one program channel
// > Default: 4 tiles × 8 threads × one 8x8 array = 256 MACs
module gpu #(
    parameter DATA_MEM_ADDR_BITS = 19,       // 1 MiB total data memory: 2^19 x 16-bit
    parameter DATA_MEM_DATA_BITS = 16,       // 16-bit SF16 fixed-point
    parameter DATA_MEM_NUM_CHANNELS = 4,     // one data channel per tile
    parameter PROGRAM_MEM_ADDR_BITS = 9,     // 512 instructions
    parameter PROGRAM_MEM_DATA_BITS = 16,    // 16 bit instruction
    parameter PROGRAM_MEM_NUM_CHANNELS = 1,  // 1 with the shared cache, else one per tile
    parameter PROGRAM_CACHE_ENTRIES = 32,    // shared instruction cache; 0 = none
    parameter NUM_CORES = 4,                 // compute tiles
    parameter THREADS_PER_BLOCK = 8,         // threads per block, one per array edge
    parameter SYSTOLIC_SIZE = 8,             // 8x8 systolic array per core
    parameter NUM_SYSTOLIC_ARRAYS = 1,       // One array per core
    parameter CACHE_SIZE = 2                 // Instruction cache entries per core (unused / reserved)
) (
    input wire clk,
    input wire reset,

    // Kernel Execution
    input wire start,
    output wire done,

    // Device Control Register
    input wire device_control_write_enable,
    input wire [7:0] device_control_data,

    // Program Memory (flattened for synthesis)
    output wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS*PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_address_flat,
    input wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS*PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_data_flat,

    // Data Memory (flattened for synthesis)
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS*DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_address_flat,
    input wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready,
    input wire [DATA_MEM_DATA_BITS*DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_data_flat,
    output wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS*DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_address_flat,
    output wire [DATA_MEM_DATA_BITS*DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_data_flat,
    input wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready,

    // Status: tile i is running a block
    output wire [NUM_CORES-1:0] core_active
);
    // ============================================
    // Pipelined reset distribution
    // Prevents reset net from becoming a
    // thousands-fanout combinational path
    // ============================================
    reg reset_pipe1, reset_pipe2;
    always @(posedge clk) begin
        reset_pipe1 <= reset;
        reset_pipe2 <= reset_pipe1;
    end

    // Control
    wire [7:0] thread_count;

    // Compute Core State
    wire [NUM_CORES-1:0] core_start;
    wire [NUM_CORES-1:0] core_reset;
    wire [NUM_CORES-1:0] core_done;
    wire [8*NUM_CORES-1:0] core_block_id_flat;
    localparam TC_BITS = $clog2(THREADS_PER_BLOCK) + 1;
    wire [TC_BITS*NUM_CORES-1:0] core_thread_count_flat;

    // Tile <> channel controllers (one program and one data port per tile)
    wire [NUM_CORES-1:0]                       tile_prog_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS*NUM_CORES-1:0] tile_prog_read_address_flat;
    wire [NUM_CORES-1:0]                       tile_prog_read_ready;
    wire [PROGRAM_MEM_DATA_BITS*NUM_CORES-1:0] tile_prog_read_data_flat;

    wire [NUM_CORES-1:0]                    tile_data_read_valid;
    wire [DATA_MEM_ADDR_BITS*NUM_CORES-1:0] tile_data_read_address_flat;
    wire [NUM_CORES-1:0]                    tile_data_read_ready;
    wire [DATA_MEM_DATA_BITS*NUM_CORES-1:0] tile_data_read_data_flat;
    wire [NUM_CORES-1:0]                    tile_data_write_valid;
    wire [DATA_MEM_ADDR_BITS*NUM_CORES-1:0] tile_data_write_address_flat;
    wire [DATA_MEM_DATA_BITS*NUM_CORES-1:0] tile_data_write_data_flat;
    wire [NUM_CORES-1:0]                    tile_data_write_ready;

    // Unused write side of the read-only program controller
    wire [NUM_CORES-1:0] prog_mem_write_ready_unused;
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] prog_ext_write_valid_unused;
    wire [PROGRAM_MEM_ADDR_BITS*PROGRAM_MEM_NUM_CHANNELS-1:0] prog_ext_write_address_flat_unused;
    wire [PROGRAM_MEM_DATA_BITS*PROGRAM_MEM_NUM_CHANNELS-1:0] prog_ext_write_data_flat_unused;

    // Device Control Register
    dcr dcr_instance (
        .clk(clk),
        .reset(reset_pipe2),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .thread_count(thread_count)
    );

    // Data Memory Controller: tiles -> external data channels
    controller #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_CORES),
        .NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
    ) data_mem_controller (
        .clk(clk),
        .reset(reset_pipe2),

        .consumer_read_valid(tile_data_read_valid),
        .consumer_read_address_flat(tile_data_read_address_flat),
        .consumer_read_ready(tile_data_read_ready),
        .consumer_read_data_flat(tile_data_read_data_flat),
        .consumer_write_valid(tile_data_write_valid),
        .consumer_write_address_flat(tile_data_write_address_flat),
        .consumer_write_data_flat(tile_data_write_data_flat),
        .consumer_write_ready(tile_data_write_ready),

        .mem_read_valid(data_mem_read_valid),
        .mem_read_address_flat(data_mem_read_address_flat),
        .mem_read_ready(data_mem_read_ready),
        .mem_read_data_flat(data_mem_read_data_flat),
        .mem_write_valid(data_mem_write_valid),
        .mem_write_address_flat(data_mem_write_address_flat),
        .mem_write_data_flat(data_mem_write_data_flat),
        .mem_write_ready(data_mem_write_ready)
    );

    // Program memory: a shared instruction cache in front of one channel, or
    // (PROGRAM_CACHE_ENTRIES = 0) a plain controller with a channel per tile.
    generate
        if (PROGRAM_CACHE_ENTRIES > 0) begin : program_cache
            shared_icache #(
                .NUM_PORTS(NUM_CORES),
                .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .ENTRIES(PROGRAM_CACHE_ENTRIES)
            ) icache (
                .clk(clk),
                .reset(reset_pipe2),
                .consumer_read_valid(tile_prog_read_valid),
                .consumer_read_address_flat(tile_prog_read_address_flat),
                .consumer_read_ready(tile_prog_read_ready),
                .consumer_read_data_flat(tile_prog_read_data_flat),
                .mem_read_valid(program_mem_read_valid[0]),
                .mem_read_address(program_mem_read_address_flat[PROGRAM_MEM_ADDR_BITS-1:0]),
                .mem_read_ready(program_mem_read_ready[0]),
                .mem_read_data(program_mem_read_data_flat[PROGRAM_MEM_DATA_BITS-1:0])
            );
        end else begin : program_controller
            controller #(
                .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .NUM_CONSUMERS(NUM_CORES),
                .NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
                .WRITE_ENABLE(0)
            ) program_mem_controller (
                .clk(clk),
                .reset(reset_pipe2),

                .consumer_read_valid(tile_prog_read_valid),
                .consumer_read_address_flat(tile_prog_read_address_flat),
                .consumer_read_ready(tile_prog_read_ready),
                .consumer_read_data_flat(tile_prog_read_data_flat),
                .consumer_write_valid({NUM_CORES{1'b0}}),
                .consumer_write_address_flat({(PROGRAM_MEM_ADDR_BITS*NUM_CORES){1'b0}}),
                .consumer_write_data_flat({(PROGRAM_MEM_DATA_BITS*NUM_CORES){1'b0}}),
                .consumer_write_ready(prog_mem_write_ready_unused),

                .mem_read_valid(program_mem_read_valid),
                .mem_read_address_flat(program_mem_read_address_flat),
                .mem_read_ready(program_mem_read_ready),
                .mem_read_data_flat(program_mem_read_data_flat),
                .mem_write_valid(prog_ext_write_valid_unused),
                .mem_write_address_flat(prog_ext_write_address_flat_unused),
                .mem_write_data_flat(prog_ext_write_data_flat_unused),
                .mem_write_ready({PROGRAM_MEM_NUM_CHANNELS{1'b0}})
            );
        end
    endgenerate

    assign core_active = core_start & ~core_done;

    // Dispatcher
    dispatch #(
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dispatch_instance (
        .clk(clk),
        .reset(reset_pipe2),
        .start(start),
        .thread_count(thread_count),
        .core_done(core_done),
        .core_start(core_start),
        .core_reset(core_reset),
        .core_block_id_flat(core_block_id_flat),
        .core_thread_count_flat(core_thread_count_flat),
        .done(done)
    );

    // Compute tiles
    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : tiles
            // With CORE_TILE_MACRO defined (chip-level harden) the tile is a
            // pre-hardened macro whose parameters were fixed at its defaults,
            // so no overrides may be passed.
            core_tile
`ifndef CORE_TILE_MACRO
            #(
                .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .SYSTOLIC_SIZE(SYSTOLIC_SIZE),
                .NUM_SYSTOLIC_ARRAYS(NUM_SYSTOLIC_ARRAYS),
                .CACHE_SIZE(CACHE_SIZE)
            )
`endif
            tile (
                .clk(clk),
                .reset(reset_pipe2),
                .core_reset(core_reset[i]),

                .start(core_start[i]),
                .done(core_done[i]),
                .block_id(core_block_id_flat[i*8 +: 8]),
                .thread_count(core_thread_count_flat[i*TC_BITS +: TC_BITS]),

                .program_mem_read_valid(tile_prog_read_valid[i]),
                .program_mem_read_address(tile_prog_read_address_flat[i*PROGRAM_MEM_ADDR_BITS +: PROGRAM_MEM_ADDR_BITS]),
                .program_mem_read_ready(tile_prog_read_ready[i]),
                .program_mem_read_data(tile_prog_read_data_flat[i*PROGRAM_MEM_DATA_BITS +: PROGRAM_MEM_DATA_BITS]),

                .data_mem_read_valid(tile_data_read_valid[i]),
                .data_mem_read_address(tile_data_read_address_flat[i*DATA_MEM_ADDR_BITS +: DATA_MEM_ADDR_BITS]),
                .data_mem_read_ready(tile_data_read_ready[i]),
                .data_mem_read_data(tile_data_read_data_flat[i*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS]),
                .data_mem_write_valid(tile_data_write_valid[i]),
                .data_mem_write_address(tile_data_write_address_flat[i*DATA_MEM_ADDR_BITS +: DATA_MEM_ADDR_BITS]),
                .data_mem_write_data(tile_data_write_data_flat[i*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS]),
                .data_mem_write_ready(tile_data_write_ready[i])
            );
        end
    endgenerate
endmodule
