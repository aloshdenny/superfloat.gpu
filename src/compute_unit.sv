`default_nettype none
`timescale 1ns/1ns

// COMPUTE UNIT (Hierarchical Design)
// > Encapsulates per-thread compute resources for cleaner physical hierarchy
// > Contains: ALU, FMA, Activation, LSU, Registers, PC
// > One compute unit per thread
module compute_unit #(
    parameter DATA_MEM_ADDR_BITS = 12,
    parameter DATA_MEM_DATA_BITS = 16,  // Q1.15 fixed-point
    parameter PROGRAM_MEM_ADDR_BITS = 12,
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Block context
    input wire [7:0] block_id,
    input wire [2:0] core_state,

    // Decoded instruction signals
    input wire [3:0] decoded_rd_address,
    input wire [3:0] decoded_rs_address,
    input wire [3:0] decoded_rt_address,
    input wire [2:0] decoded_nzp,
    input wire [7:0] decoded_immediate,
    input wire decoded_reg_write_enable,
    input wire decoded_mem_read_enable,
    input wire decoded_mem_write_enable,
    input wire decoded_nzp_write_enable,
    input wire [2:0] decoded_reg_input_mux,
    input wire [1:0] decoded_alu_arithmetic_mux,
    input wire decoded_alu_output_mux,
    input wire decoded_pc_mux,
    input wire decoded_fma_enable,
    input wire decoded_act_enable,
    input wire [1:0] decoded_act_func,

    // Current PC from scheduler
    input wire [7:0] current_pc,

    // Memory interface
    output reg mem_read_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_MEM_DATA_BITS-1:0] mem_read_data,
    output reg mem_write_valid,
    output reg [DATA_MEM_ADDR_BITS-1:0] mem_write_address,
    output reg [DATA_MEM_DATA_BITS-1:0] mem_write_data,
    input wire mem_write_ready,

    // Outputs
    output wire [7:0] next_pc,
    output reg [1:0] lsu_state
);

    // Internal signals
    reg [DATA_MEM_DATA_BITS-1:0] rs;
    reg [DATA_MEM_DATA_BITS-1:0] rt;
    reg [DATA_MEM_DATA_BITS-1:0] lsu_out;
    wire [DATA_MEM_DATA_BITS-1:0] alu_out;
    wire [DATA_MEM_DATA_BITS-1:0] fma_out;
    wire [DATA_MEM_DATA_BITS-1:0] act_out;
    reg [DATA_MEM_DATA_BITS-1:0] rd_value;

    // ALU (Integer arithmetic for indexing)
    alu #(
        .DATA_BITS(DATA_MEM_DATA_BITS)
    ) alu_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
        .decoded_alu_output_mux(decoded_alu_output_mux),
        .rs(rs),
        .rt(rt),
        .alu_out(alu_out)
    );

    // FMA Unit (Q1.15 multiply-accumulate)
    fma #(
        .DATA_BITS(DATA_MEM_DATA_BITS)
    ) fma_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .decoded_fma_enable(decoded_fma_enable),
        .rs(rs),
        .rt(rt),
        .rq(rd_value),
        .fma_out(fma_out)
    );

    // Activation Unit
    activation #(
        .DATA_BITS(DATA_MEM_DATA_BITS)
    ) activation_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .activation_enable(decoded_act_enable),
        .activation_func(decoded_act_func),
        .unbiased_activation(rs),
        .bias(rt),
        .activation_out(act_out)
    );

    // LSU (Load-Store Unit)
    lsu #(
        .ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_BITS(DATA_MEM_DATA_BITS)
    ) lsu_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .decoded_mem_read_enable(decoded_mem_read_enable),
        .decoded_mem_write_enable(decoded_mem_write_enable),
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data),
        .mem_write_valid(mem_write_valid),
        .mem_write_address(mem_write_address),
        .mem_write_data(mem_write_data),
        .mem_write_ready(mem_write_ready),
        .rs(rs),
        .rt(rt),
        .lsu_state(lsu_state),
        .lsu_out(lsu_out)
    );

    // Register File
    registers #(
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .THREAD_ID(THREAD_ID),
        .DATA_BITS(DATA_MEM_DATA_BITS)
    ) register_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .block_id(block_id),
        .core_state(core_state),
        .decoded_reg_write_enable(decoded_reg_write_enable),
        .decoded_reg_input_mux(decoded_reg_input_mux),
        .decoded_rd_address(decoded_rd_address),
        .decoded_rs_address(decoded_rs_address),
        .decoded_rt_address(decoded_rt_address),
        .decoded_immediate(decoded_immediate),
        .alu_out(alu_out),
        .lsu_out(lsu_out),
        .fma_out(fma_out),
        .act_out(act_out),
        .rs(rs),
        .rt(rt)
    );

    // Program Counter
    pc #(
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
    ) pc_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .decoded_nzp(decoded_nzp),
        .decoded_immediate(decoded_immediate),
        .decoded_nzp_write_enable(decoded_nzp_write_enable),
        .decoded_pc_mux(decoded_pc_mux),
        .alu_out(alu_out),
        .current_pc(current_pc),
        .next_pc(next_pc)
    );

    // Capture Rd value for FMA accumulator
    always @(posedge clk) begin
        if (reset) begin
            rd_value <= {DATA_MEM_DATA_BITS{1'b0}};
        end else if (core_state == 3'b011) begin  // REQUEST state
            rd_value <= rs;
        end
    end

endmodule
