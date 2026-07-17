`default_nettype none
`timescale 1ns/1ns

// GPU - ATREIDES NEURAL NETWORK ACCELERATOR
// > Built to use an external async memory with multi-channel read/write
// > Assumes that the program is loaded into program memory, data into data memory, and threads into
//   the device control register before the start signal is triggered
// > Has memory controllers to interface between external memory and its multiple cores
// > Configurable number of cores and thread capacity per core
// > Owns the instruction set decode for all cores
// > 2 cores, 2 threads/block, one 2x2 systolic array per core (8x4 lightweight)
// > Hierarchical design for improved physical synthesis
module gpu #(
    parameter DATA_MEM_ADDR_BITS = 19,       // 1 MiB total data memory: 2^19 x 16-bit
    parameter DATA_MEM_DATA_BITS = 16,       // 16-bit SF16 fixed-point
    parameter DATA_MEM_NUM_CHANNELS = 4,     // 4 channels for 2 cores × 2 threads
    parameter PROGRAM_MEM_ADDR_BITS = 9,     // 512 instructions
    parameter PROGRAM_MEM_DATA_BITS = 16,    // 16 bit instruction
    parameter PROGRAM_MEM_NUM_CHANNELS = 2,  // 2 channels for 2 cores
    parameter NUM_CORES = 2,                 // 2 compute cores
    parameter THREADS_PER_BLOCK = 2,         // 2 threads per block
    parameter SYSTOLIC_SIZE = 2,             // 2x2 systolic array per core
    parameter NUM_SYSTOLIC_ARRAYS = 1,       // One array per core
    parameter CACHE_SIZE = 2                // Instruction cache entries per core (unused / reserved)
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
    input wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready
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
    
    // Unflatten for core access
    wire [7:0] core_block_id [NUM_CORES-1:0];
    wire [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0];
    
    genvar blk_idx;
    generate
        for (blk_idx = 0; blk_idx < NUM_CORES; blk_idx = blk_idx + 1) begin : unflatten_dispatch
            assign core_block_id[blk_idx] = core_block_id_flat[(blk_idx+1)*8-1 -: 8];
            assign core_thread_count[blk_idx] = core_thread_count_flat[(blk_idx+1)*TC_BITS-1 -: TC_BITS];
        end
    endgenerate

    // LSU <> Data Memory Controller Channels (flattened)
    // LSU <> Data Memory Controller Channels (flattened)
    localparam NUM_LSUS = NUM_CORES * THREADS_PER_BLOCK;
    wire [NUM_LSUS-1:0] lsu_read_valid;
    wire [DATA_MEM_ADDR_BITS*NUM_LSUS-1:0] lsu_read_address_flat;
    wire [NUM_LSUS-1:0] lsu_read_ready;
    wire [DATA_MEM_DATA_BITS*NUM_LSUS-1:0] lsu_read_data_flat;
    wire [NUM_LSUS-1:0] lsu_write_valid;
    wire [DATA_MEM_ADDR_BITS*NUM_LSUS-1:0] lsu_write_address_flat;
    wire [DATA_MEM_DATA_BITS*NUM_LSUS-1:0] lsu_write_data_flat;
    wire [NUM_LSUS-1:0] lsu_write_ready;

    // Internal unpacked arrays for per-LSU access
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_read_address [NUM_LSUS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] lsu_read_data [NUM_LSUS-1:0];
    wire [DATA_MEM_ADDR_BITS-1:0] lsu_write_address [NUM_LSUS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] lsu_write_data [NUM_LSUS-1:0];
    
    // Unflatten read data and flatten output signals (parameterized)
    genvar lsu_idx;
    generate
        for (lsu_idx = 0; lsu_idx < NUM_LSUS; lsu_idx = lsu_idx + 1) begin : lsu_flatten_unflatten
            assign lsu_read_data[lsu_idx] = lsu_read_data_flat[(lsu_idx+1)*DATA_MEM_DATA_BITS-1 : lsu_idx*DATA_MEM_DATA_BITS];
            assign lsu_read_address_flat[(lsu_idx+1)*DATA_MEM_ADDR_BITS-1 : lsu_idx*DATA_MEM_ADDR_BITS] = lsu_read_address[lsu_idx];
            assign lsu_write_address_flat[(lsu_idx+1)*DATA_MEM_ADDR_BITS-1 : lsu_idx*DATA_MEM_ADDR_BITS] = lsu_write_address[lsu_idx];
            assign lsu_write_data_flat[(lsu_idx+1)*DATA_MEM_DATA_BITS-1 : lsu_idx*DATA_MEM_DATA_BITS] = lsu_write_data[lsu_idx];
        end
    endgenerate

    // Fetcher <> Program Memory Controller Channels (flattened)
    localparam NUM_FETCHERS = NUM_CORES;
    wire [NUM_FETCHERS-1:0] fetcher_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS*NUM_FETCHERS-1:0] fetcher_read_address_flat;
    wire [NUM_FETCHERS-1:0] fetcher_read_ready;
    wire [PROGRAM_MEM_DATA_BITS*NUM_FETCHERS-1:0] fetcher_read_data_flat;
    
    // Internal unpacked arrays for per-fetcher access
    wire [PROGRAM_MEM_ADDR_BITS-1:0] fetcher_read_address [NUM_FETCHERS-1:0];
    wire [PROGRAM_MEM_DATA_BITS-1:0] fetcher_read_data [NUM_FETCHERS-1:0];
    
    // Flatten/unflatten fetcher signals (parameterized)
    genvar f_idx;
    generate
        for (f_idx = 0; f_idx < NUM_FETCHERS; f_idx = f_idx + 1) begin : fetcher_flatten
            assign fetcher_read_address_flat[(f_idx+1)*PROGRAM_MEM_ADDR_BITS-1 : f_idx*PROGRAM_MEM_ADDR_BITS] = fetcher_read_address[f_idx];
            assign fetcher_read_data[f_idx] = fetcher_read_data_flat[(f_idx+1)*PROGRAM_MEM_DATA_BITS-1 : f_idx*PROGRAM_MEM_DATA_BITS];
        end
    endgenerate
    
    // Unused write signals for program memory controller (read-only) - flattened
    wire [NUM_FETCHERS-1:0] prog_mem_write_ready_unused;
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] prog_ext_write_valid_unused;
    wire [PROGRAM_MEM_ADDR_BITS*PROGRAM_MEM_NUM_CHANNELS-1:0] prog_ext_write_address_flat_unused;
    wire [PROGRAM_MEM_DATA_BITS*PROGRAM_MEM_NUM_CHANNELS-1:0] prog_ext_write_data_flat_unused;
    wire [PROGRAM_MEM_ADDR_BITS*NUM_FETCHERS-1:0] fetcher_write_address_flat_unused;
    wire [PROGRAM_MEM_DATA_BITS*NUM_FETCHERS-1:0] fetcher_write_data_flat_unused;

    // Input signals to read-only controller need to be driven with constants
    assign fetcher_write_address_flat_unused = {(PROGRAM_MEM_ADDR_BITS*NUM_FETCHERS){1'b0}};
    assign fetcher_write_data_flat_unused = {(PROGRAM_MEM_DATA_BITS*NUM_FETCHERS){1'b0}};
    // Note: prog_ext_write_* are outputs from controller, driven by controller (will be 0 when WRITE_ENABLE=0)
    
    // Device Control Register
    dcr dcr_instance (
        .clk(clk),
        .reset(reset_pipe2),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .thread_count(thread_count)
    );

    // Memory Controller - Main interface to external memory
    controller #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_LSUS),
        .NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
    ) data_mem_controller (
        .clk(clk),
        .reset(reset_pipe2),

        .consumer_read_valid(lsu_read_valid),
        .consumer_read_address_flat(lsu_read_address_flat),
        .consumer_read_ready(lsu_read_ready),
        .consumer_read_data_flat(lsu_read_data_flat),
        .consumer_write_valid(lsu_write_valid),
        .consumer_write_address_flat(lsu_write_address_flat),
        .consumer_write_data_flat(lsu_write_data_flat),
        .consumer_write_ready(lsu_write_ready),

        .mem_read_valid(data_mem_read_valid),
        .mem_read_address_flat(data_mem_read_address_flat),
        .mem_read_ready(data_mem_read_ready),
        .mem_read_data_flat(data_mem_read_data_flat),
        .mem_write_valid(data_mem_write_valid),
        .mem_write_address_flat(data_mem_write_address_flat),
        .mem_write_data_flat(data_mem_write_data_flat),
        .mem_write_ready(data_mem_write_ready)
    );

    // Program Memory Controller
    controller #(
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .NUM_CONSUMERS(NUM_CORES),
        .NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS)
    ) program_mem_controller (
        .clk(clk),
        .reset(reset_pipe2),

        .consumer_read_valid(fetcher_read_valid),
        .consumer_read_address_flat(fetcher_read_address_flat),
        .consumer_read_ready(fetcher_read_ready),
        .consumer_read_data_flat(fetcher_read_data_flat),
        .consumer_write_valid({NUM_FETCHERS{1'b0}}),
        .consumer_write_address_flat(fetcher_write_address_flat_unused),
        .consumer_write_data_flat(fetcher_write_data_flat_unused),
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

    // Compute Cores
    genvar i;
    generate
        for (i = 0; i < NUM_CORES; i = i + 1) begin : cores
            // Flattened core interface signals
            wire [THREADS_PER_BLOCK-1:0] core_lsu_read_valid;
            wire [DATA_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] core_lsu_read_address_flat;
            wire [THREADS_PER_BLOCK-1:0] core_lsu_read_ready;
            wire [DATA_MEM_DATA_BITS*THREADS_PER_BLOCK-1:0] core_lsu_read_data_flat;
            wire [THREADS_PER_BLOCK-1:0] core_lsu_write_valid;
            wire [DATA_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] core_lsu_write_address_flat;
            wire [DATA_MEM_DATA_BITS*THREADS_PER_BLOCK-1:0] core_lsu_write_data_flat;
            wire [THREADS_PER_BLOCK-1:0] core_lsu_write_ready;
            
            // Unflatten core signals for controller interface
            wire [DATA_MEM_ADDR_BITS-1:0] core_lsu_read_address [THREADS_PER_BLOCK-1:0];
            wire [DATA_MEM_DATA_BITS-1:0] core_lsu_read_data [THREADS_PER_BLOCK-1:0];
            wire [DATA_MEM_ADDR_BITS-1:0] core_lsu_write_address [THREADS_PER_BLOCK-1:0];
            wire [DATA_MEM_DATA_BITS-1:0] core_lsu_write_data [THREADS_PER_BLOCK-1:0];

            // GPU-owned ISA decode for this core
            wire [2:0] core_state_for_decode;
            wire [15:0] core_instruction;
            wire [3:0] decoded_rd_address;
            wire [3:0] decoded_rs_address;
            wire [3:0] decoded_rt_address;
            wire [2:0] decoded_nzp;
            wire [7:0] decoded_immediate;
            wire decoded_reg_write_enable;
            wire decoded_mem_read_enable;
            wire decoded_mem_write_enable;
            wire decoded_nzp_write_enable;
            wire [2:0] decoded_reg_input_mux;
            wire [1:0] decoded_alu_arithmetic_mux;
            wire decoded_alu_output_mux;
            wire decoded_pc_mux;
            wire decoded_fma_enable;
            wire decoded_act_enable;
            wire [1:0] decoded_act_func;
            wire decoded_systolic_enable;
            wire [1:0] decoded_systolic_op;
            wire decoded_systolic_idx;
            wire decoded_branch;
            wire decoded_ret;
            
            // Unflatten core signals for controller interface using generate
            genvar t;
            for (t = 0; t < THREADS_PER_BLOCK; t = t + 1) begin : unflatten_lsu
                assign core_lsu_read_address[t] = core_lsu_read_address_flat[(t+1)*DATA_MEM_ADDR_BITS-1 : t*DATA_MEM_ADDR_BITS];
                assign core_lsu_write_address[t] = core_lsu_write_address_flat[(t+1)*DATA_MEM_ADDR_BITS-1 : t*DATA_MEM_ADDR_BITS];
                assign core_lsu_write_data[t] = core_lsu_write_data_flat[(t+1)*DATA_MEM_DATA_BITS-1 : t*DATA_MEM_DATA_BITS];
            end

            decoder decoder_instance (
                .clk(clk),
                .reset(reset_pipe2),
                .core_state(core_state_for_decode),
                .instruction(core_instruction),
                .decoded_rd_address(decoded_rd_address),
                .decoded_rs_address(decoded_rs_address),
                .decoded_rt_address(decoded_rt_address),
                .decoded_nzp(decoded_nzp),
                .decoded_immediate(decoded_immediate),
                .decoded_reg_write_enable(decoded_reg_write_enable),
                .decoded_mem_read_enable(decoded_mem_read_enable),
                .decoded_mem_write_enable(decoded_mem_write_enable),
                .decoded_nzp_write_enable(decoded_nzp_write_enable),
                .decoded_reg_input_mux(decoded_reg_input_mux),
                .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
                .decoded_alu_output_mux(decoded_alu_output_mux),
                .decoded_pc_mux(decoded_pc_mux),
                .decoded_fma_enable(decoded_fma_enable),
                .decoded_act_enable(decoded_act_enable),
                .decoded_act_func(decoded_act_func),
                .decoded_systolic_enable(decoded_systolic_enable),
                .decoded_systolic_op(decoded_systolic_op),
                .decoded_systolic_idx(decoded_systolic_idx),
                .decoded_branch(decoded_branch),
                .decoded_ret(decoded_ret)
            );
            
            // Compute core execution engine
            core #(
                .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
                .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .SYSTOLIC_SIZE(SYSTOLIC_SIZE),
                .NUM_SYSTOLIC_ARRAYS(NUM_SYSTOLIC_ARRAYS),
                .CACHE_SIZE(CACHE_SIZE)
            ) core_instance (
                .clk(clk),
                .reset(core_reset[i]),
                .start(core_start[i]),
                .done(core_done[i]),
                .block_id(core_block_id[i]),
                .thread_count(core_thread_count[i]),

                .core_state_for_decode(core_state_for_decode),
                .instruction_for_decode(core_instruction),
                .decoded_rd_address(decoded_rd_address),
                .decoded_rs_address(decoded_rs_address),
                .decoded_rt_address(decoded_rt_address),
                .decoded_nzp(decoded_nzp),
                .decoded_immediate(decoded_immediate),
                .decoded_reg_write_enable(decoded_reg_write_enable),
                .decoded_mem_read_enable(decoded_mem_read_enable),
                .decoded_mem_write_enable(decoded_mem_write_enable),
                .decoded_nzp_write_enable(decoded_nzp_write_enable),
                .decoded_reg_input_mux(decoded_reg_input_mux),
                .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
                .decoded_alu_output_mux(decoded_alu_output_mux),
                .decoded_pc_mux(decoded_pc_mux),
                .decoded_fma_enable(decoded_fma_enable),
                .decoded_act_enable(decoded_act_enable),
                .decoded_act_func(decoded_act_func),
                .decoded_systolic_enable(decoded_systolic_enable),
                .decoded_systolic_op(decoded_systolic_op),
                .decoded_systolic_idx(decoded_systolic_idx),
                .decoded_branch(decoded_branch),
                .decoded_ret(decoded_ret),
                
                .program_mem_read_valid(fetcher_read_valid[i]),
                .program_mem_read_address(fetcher_read_address[i]),
                .program_mem_read_ready(fetcher_read_ready[i]),
                .program_mem_read_data(fetcher_read_data[i]),

                .data_mem_read_valid(core_lsu_read_valid),
                .data_mem_read_address_flat(core_lsu_read_address_flat),
                .data_mem_read_ready(core_lsu_read_ready),
                .data_mem_read_data_flat(core_lsu_read_data_flat),
                .data_mem_write_valid(core_lsu_write_valid),
                .data_mem_write_address_flat(core_lsu_write_address_flat),
                .data_mem_write_data_flat(core_lsu_write_data_flat),
                .data_mem_write_ready(core_lsu_write_ready)
            );

            // LSU Passthrough logic - purely combinational to allow memory controller to handle timing
            genvar t2;
            for (t2 = 0; t2 < THREADS_PER_BLOCK; t2 = t2 + 1) begin : lsu_passthrough_assign
                assign lsu_read_valid [i*THREADS_PER_BLOCK + t2] = core_lsu_read_valid[t2];
                assign lsu_read_address[i*THREADS_PER_BLOCK + t2] = core_lsu_read_address[t2];
                assign lsu_write_valid [i*THREADS_PER_BLOCK + t2] = core_lsu_write_valid[t2];
                assign lsu_write_address[i*THREADS_PER_BLOCK + t2] = core_lsu_write_address[t2];
                assign lsu_write_data  [i*THREADS_PER_BLOCK + t2] = core_lsu_write_data[t2];
                
                assign core_lsu_read_ready[t2] = lsu_read_ready[i*THREADS_PER_BLOCK + t2];
                assign core_lsu_read_data[t2] = lsu_read_data[i*THREADS_PER_BLOCK + t2];
                assign core_lsu_write_ready[t2] = lsu_write_ready[i*THREADS_PER_BLOCK + t2];
            end

            // Flatten read data combinationally
            for (t2 = 0; t2 < THREADS_PER_BLOCK; t2 = t2 + 1) begin : lsu_rd_flatten
                assign core_lsu_read_data_flat[t2*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS] = 
                       core_lsu_read_data[t2];
            end
        end
    endgenerate
endmodule
