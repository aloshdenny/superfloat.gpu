`default_nettype none
`timescale 1ns/1ns

// CORE TILE — the hardened compute macro for the OpenFrame chip
// > One compute core (THREADS_PER_BLOCK threads + one SYSTOLIC_SIZE^2 array)
// > NUMBER_FORMAT fixes the arithmetic (0 SF16, 1 FP16, 2 BF16); each format
//   is hardened as its own macro
// > Its own instruction decoder
// > Its own 128B address-mapped scratchpad (0xFFC0..0xFFFF), private to the core
// > One arbitrated data-memory port: the per-thread LSUs share it, so the
//   top level sees one data channel and one program channel per tile
//
// Two resets: `reset` is the chip reset (decoder, scratchpad, arbiter);
// `core_reset` comes from the dispatcher and restarts the core per block.
module core_tile #(
    parameter DATA_MEM_ADDR_BITS = 19,
    parameter DATA_MEM_DATA_BITS = 16,
    parameter PROGRAM_MEM_ADDR_BITS = 9,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter THREADS_PER_BLOCK = 8,
    parameter SYSTOLIC_SIZE = 8,
    parameter NUM_SYSTOLIC_ARRAYS = 1,
    parameter CACHE_SIZE = 2,
    parameter NUMBER_FORMAT = 0             // 0 SF16, 1 FP16, 2 BF16
) (
    input  wire clk,
    input  wire reset,
    input  wire core_reset,

    // Kernel execution
    input  wire start,
    output wire done,
    input  wire [7:0] block_id,
    input  wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // Program memory channel
    output wire                             program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input  wire                             program_mem_read_ready,
    input  wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    // Data memory channel
    output wire                          data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address,
    input  wire                          data_mem_read_ready,
    input  wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data,
    output wire                          data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address,
    output wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data,
    input  wire                          data_mem_write_ready
);
    // ============================================
    // Instruction decode
    // ============================================
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

    decoder decoder_instance (
        .clk(clk),
        .reset(reset),
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

    // ============================================
    // Compute core
    // ============================================
    wire [THREADS_PER_BLOCK-1:0]                    lsu_read_valid;
    wire [DATA_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] lsu_read_address_flat;
    wire [THREADS_PER_BLOCK-1:0]                    lsu_read_ready;
    wire [DATA_MEM_DATA_BITS*THREADS_PER_BLOCK-1:0] lsu_read_data_flat;
    wire [THREADS_PER_BLOCK-1:0]                    lsu_write_valid;
    wire [DATA_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] lsu_write_address_flat;
    wire [DATA_MEM_DATA_BITS*THREADS_PER_BLOCK-1:0] lsu_write_data_flat;
    wire [THREADS_PER_BLOCK-1:0]                    lsu_write_ready;

    core #(
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .SYSTOLIC_SIZE(SYSTOLIC_SIZE),
        .NUM_SYSTOLIC_ARRAYS(NUM_SYSTOLIC_ARRAYS),
        .CACHE_SIZE(CACHE_SIZE),
        .NUMBER_FORMAT(NUMBER_FORMAT)
    ) core_instance (
        .clk(clk),
        .reset(core_reset),
        .start(start),
        .done(done),
        .block_id(block_id),
        .thread_count(thread_count),

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

        .program_mem_read_valid(program_mem_read_valid),
        .program_mem_read_address(program_mem_read_address),
        .program_mem_read_ready(program_mem_read_ready),
        .program_mem_read_data(program_mem_read_data),

        .data_mem_read_valid(lsu_read_valid),
        .data_mem_read_address_flat(lsu_read_address_flat),
        .data_mem_read_ready(lsu_read_ready),
        .data_mem_read_data_flat(lsu_read_data_flat),
        .data_mem_write_valid(lsu_write_valid),
        .data_mem_write_address_flat(lsu_write_address_flat),
        .data_mem_write_data_flat(lsu_write_data_flat),
        .data_mem_write_ready(lsu_write_ready)
    );

    // ============================================
    // Per-core scratchpad: hits stay in the tile, misses go to the arbiter
    // ============================================
    wire [THREADS_PER_BLOCK-1:0]                    miss_read_valid;
    wire [DATA_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] miss_read_address_flat;
    wire [THREADS_PER_BLOCK-1:0]                    miss_read_ready;
    wire [DATA_MEM_DATA_BITS*THREADS_PER_BLOCK-1:0] miss_read_data_flat;
    wire [THREADS_PER_BLOCK-1:0]                    miss_write_valid;
    wire [DATA_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] miss_write_address_flat;
    wire [DATA_MEM_DATA_BITS*THREADS_PER_BLOCK-1:0] miss_write_data_flat;
    wire [THREADS_PER_BLOCK-1:0]                    miss_write_ready;

    wire        scratch_ram_en;
    wire [3:0]  scratch_ram_we;
    wire [4:0]  scratch_ram_addr;
    wire [31:0] scratch_ram_di;
    wire [31:0] scratch_ram_do;

    scratchpad #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_PORTS(THREADS_PER_BLOCK)
    ) data_scratchpad (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(lsu_read_valid),
        .consumer_read_address_flat(lsu_read_address_flat),
        .consumer_read_ready(lsu_read_ready),
        .consumer_read_data_flat(lsu_read_data_flat),
        .consumer_write_valid(lsu_write_valid),
        .consumer_write_address_flat(lsu_write_address_flat),
        .consumer_write_data_flat(lsu_write_data_flat),
        .consumer_write_ready(lsu_write_ready),

        .mem_read_valid(miss_read_valid),
        .mem_read_address_flat(miss_read_address_flat),
        .mem_read_ready(miss_read_ready),
        .mem_read_data_flat(miss_read_data_flat),
        .mem_write_valid(miss_write_valid),
        .mem_write_address_flat(miss_write_address_flat),
        .mem_write_data_flat(miss_write_data_flat),
        .mem_write_ready(miss_write_ready),

        .ram_en(scratch_ram_en),
        .ram_we(scratch_ram_we),
        .ram_addr(scratch_ram_addr),
        .ram_di(scratch_ram_di),
        .ram_do(scratch_ram_do)
    );

    RAM32 scratch_ram (
        .CLK (clk),
        .EN0 (scratch_ram_en),
        .WE0 (scratch_ram_we),
        .A0  (scratch_ram_addr),
        .Di0 (scratch_ram_di),
        .Do0 (scratch_ram_do)
    );

    // ============================================
    // Miss arbiter: THREADS_PER_BLOCK LSUs -> one data channel
    // ============================================
    controller #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .NUM_CONSUMERS(THREADS_PER_BLOCK),
        .NUM_CHANNELS(1)
    ) data_mem_arbiter (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(miss_read_valid),
        .consumer_read_address_flat(miss_read_address_flat),
        .consumer_read_ready(miss_read_ready),
        .consumer_read_data_flat(miss_read_data_flat),
        .consumer_write_valid(miss_write_valid),
        .consumer_write_address_flat(miss_write_address_flat),
        .consumer_write_data_flat(miss_write_data_flat),
        .consumer_write_ready(miss_write_ready),

        .mem_read_valid(data_mem_read_valid),
        .mem_read_address_flat(data_mem_read_address),
        .mem_read_ready(data_mem_read_ready),
        .mem_read_data_flat(data_mem_read_data),
        .mem_write_valid(data_mem_write_valid),
        .mem_write_address_flat(data_mem_write_address),
        .mem_write_data_flat(data_mem_write_data),
        .mem_write_ready(data_mem_write_ready)
    );
endmodule
