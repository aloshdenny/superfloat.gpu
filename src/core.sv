`default_nettype none
`timescale 1ns/1ns

// COMPUTE CORE (Q1.15 Fixed-Point with Neural Network Support)
// > Handles processing 1 block at a time
// > Each core contains 1 fetcher & decoder, and per-thread: registers, ALU, FMA, Activation, LSU, PC
// > Includes optional systolic array for accelerated matrix operations
// > Supports neural network operations: FMA for matmul, ACT for activation functions
module core #(
    parameter DATA_MEM_ADDR_BITS = 8,
    parameter DATA_MEM_DATA_BITS = 16,  // Q1.15 fixed-point (16-bit)
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter THREADS_PER_BLOCK = 4,
    parameter SYSTOLIC_SIZE = 4,        // Configurable systolic array size
    parameter CACHE_SIZE = 16           // Instruction cache size
) (
    input wire clk,
    input wire reset,

    // Kernel Execution
    input wire start,
    output wire done,

    // Block Metadata
    input wire [7:0] block_id,
    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // Program Memory
    output reg program_mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input reg program_mem_read_ready,
    input reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    // Data Memory (16-bit Q1.15)
    output reg [THREADS_PER_BLOCK-1:0] data_mem_read_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [THREADS_PER_BLOCK-1:0],
    input reg [THREADS_PER_BLOCK-1:0] data_mem_read_ready,
    input reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [THREADS_PER_BLOCK-1:0],
    output reg [THREADS_PER_BLOCK-1:0] data_mem_write_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [THREADS_PER_BLOCK-1:0],
    output reg [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [THREADS_PER_BLOCK-1:0],
    input reg [THREADS_PER_BLOCK-1:0] data_mem_write_ready
);
    // State
    reg [2:0] core_state;
    reg [2:0] fetcher_state;
    reg [15:0] instruction;

    // Intermediate Signals (16-bit Q1.15)
    reg [7:0] current_pc;
    wire [7:0] next_pc[THREADS_PER_BLOCK-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] rs[THREADS_PER_BLOCK-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] rt[THREADS_PER_BLOCK-1:0];
    reg [1:0] lsu_state[THREADS_PER_BLOCK-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] lsu_out[THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] alu_out[THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] fma_out[THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] act_out[THREADS_PER_BLOCK-1:0];
    
    // Decoded Instruction Signals
    reg [3:0] decoded_rd_address;
    reg [3:0] decoded_rs_address;
    reg [3:0] decoded_rt_address;
    reg [2:0] decoded_nzp;
    reg [7:0] decoded_immediate;

    // Decoded Control Signals
    reg decoded_reg_write_enable;
    reg decoded_mem_read_enable;
    reg decoded_mem_write_enable;
    reg decoded_nzp_write_enable;
    reg [2:0] decoded_reg_input_mux;        // 3-bit: 000=ALU, 001=MEM, 010=CONST, 011=FMA, 100=ACT
    reg [1:0] decoded_alu_arithmetic_mux;
    reg decoded_alu_output_mux;
    reg decoded_pc_mux;
    reg decoded_fma_enable;
    reg decoded_act_enable;
    reg [1:0] decoded_act_func;
    reg decoded_ret;

    // For FMA: accumulator input from destination register
    reg [DATA_MEM_DATA_BITS-1:0] rd_value[THREADS_PER_BLOCK-1:0];

    // Fetcher
    fetcher #(
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS)
    ) fetcher_instance (
        .clk(clk),
        .reset(reset),
        .core_state(core_state),
        .current_pc(current_pc),
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
        .fetcher_state(fetcher_state),
        .instruction(instruction) 
    );

    // Decoder
    decoder decoder_instance (
        .clk(clk),
        .reset(reset),
        .core_state(core_state),
        .instruction(instruction),
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
        .decoded_ret(decoded_ret)
    );

    // Scheduler
    scheduler #(
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) scheduler_instance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .fetcher_state(fetcher_state),
        .core_state(core_state),
        .decoded_mem_read_enable(decoded_mem_read_enable),
        .decoded_mem_write_enable(decoded_mem_write_enable),
        .decoded_ret(decoded_ret),
        .lsu_state(lsu_state),
        .current_pc(current_pc),
        .next_pc(next_pc),
        .done(done)
    );

    // Per-thread compute units
    genvar i;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : threads
            // ALU (Integer arithmetic for indexing)
            alu #(
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) alu_instance (
                .clk(clk),
                .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
                .decoded_alu_output_mux(decoded_alu_output_mux),
                .rs(rs[i]),
                .rt(rt[i]),
                .alu_out(alu_out[i])
            );

            // Optimized FMA Unit (Q1.15 multiply-accumulate)
            fma #(
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) fma_instance (
                .clk(clk),
                .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .decoded_fma_enable(decoded_fma_enable),
                .rs(rs[i]),
                .rt(rt[i]),
                .rq(rd_value[i]),
                .fma_out(fma_out[i])
            );

            // Activation Unit (Bias + Activation function)
            activation #(
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) activation_instance (
                .clk(clk),
                .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .activation_enable(decoded_act_enable),
                .activation_func(decoded_act_func),
                .unbiased_activation(rs[i]),  // Input activation
                .bias(rt[i]),                  // Bias from Rt
                .activation_out(act_out[i])
            );

            // LSU (16-bit memory transfers)
            lsu #(
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) lsu_instance (
                .clk(clk),
                .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .decoded_mem_read_enable(decoded_mem_read_enable),
                .decoded_mem_write_enable(decoded_mem_write_enable),
                .mem_read_valid(data_mem_read_valid[i]),
                .mem_read_address(data_mem_read_address[i]),
                .mem_read_ready(data_mem_read_ready[i]),
                .mem_read_data(data_mem_read_data[i]),
                .mem_write_valid(data_mem_write_valid[i]),
                .mem_write_address(data_mem_write_address[i]),
                .mem_write_data(data_mem_write_data[i]),
                .mem_write_ready(data_mem_write_ready[i]),
                .rs(rs[i]),
                .rt(rt[i]),
                .lsu_state(lsu_state[i]),
                .lsu_out(lsu_out[i])
            );

            // Register File (16-bit)
            registers #(
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .THREAD_ID(i),
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) register_instance (
                .clk(clk),
                .reset(reset),
                .enable(i < thread_count),
                .block_id(block_id),
                .core_state(core_state),
                .decoded_reg_write_enable(decoded_reg_write_enable),
                .decoded_reg_input_mux(decoded_reg_input_mux),
                .decoded_rd_address(decoded_rd_address),
                .decoded_rs_address(decoded_rs_address),
                .decoded_rt_address(decoded_rt_address),
                .decoded_immediate(decoded_immediate),
                .alu_out(alu_out[i]),
                .lsu_out(lsu_out[i]),
                .fma_out(fma_out[i]),
                .act_out(act_out[i]),
                .rs(rs[i]),
                .rt(rt[i])
            );

            // Program Counter
            pc #(
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
            ) pc_instance (
                .clk(clk),
                .reset(reset),
                .enable(i < thread_count),
                .core_state(core_state),
                .decoded_nzp(decoded_nzp),
                .decoded_immediate(decoded_immediate),
                .decoded_nzp_write_enable(decoded_nzp_write_enable),
                .decoded_pc_mux(decoded_pc_mux),
                .alu_out(alu_out[i]),
                .current_pc(current_pc),
                .next_pc(next_pc[i])
            );

            // Capture Rd value for FMA accumulator
            always @(posedge clk) begin
                if (reset) begin
                    rd_value[i] <= {DATA_MEM_DATA_BITS{1'b0}};
                end else if (core_state == 3'b011) begin  // REQUEST state
                    rd_value[i] <= rs[i];
                end
            end
        end
    endgenerate

    // ============================================
    // Systolic Array (shared accelerator)
    // ============================================
    wire [DATA_MEM_DATA_BITS-1:0] systolic_results [SYSTOLIC_SIZE-1:0][SYSTOLIC_SIZE-1:0];
    wire systolic_ready;

    wire signed [DATA_MEM_DATA_BITS-1:0] systolic_a_inputs [SYSTOLIC_SIZE-1:0];
    wire signed [DATA_MEM_DATA_BITS-1:0] systolic_b_inputs [SYSTOLIC_SIZE-1:0];

    genvar sa_idx;
    generate
        for (sa_idx = 0; sa_idx < SYSTOLIC_SIZE; sa_idx = sa_idx + 1) begin : systolic_input_init
            assign systolic_a_inputs[sa_idx] = {DATA_MEM_DATA_BITS{1'b0}};
            assign systolic_b_inputs[sa_idx] = {DATA_MEM_DATA_BITS{1'b0}};
        end
    endgenerate

    systolic_array #(
        .DATA_BITS(DATA_MEM_DATA_BITS),
        .ARRAY_SIZE(SYSTOLIC_SIZE)
    ) systolic_instance (
        .clk(clk),
        .reset(reset),
        .enable(1'b1),
        .clear_acc(reset),
        .load_weights(1'b0),
        .compute_enable(1'b0),
        .a_inputs(systolic_a_inputs),
        .b_inputs(systolic_b_inputs),
        .results(systolic_results),
        .ready(systolic_ready)
    );

endmodule
