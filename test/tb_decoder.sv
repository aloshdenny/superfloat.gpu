`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for Instruction Decoder
// Provides direct access to decoder signals for cocotb testing
module tb_decoder (
    input wire clk,
    input wire reset,
    
    // Control inputs
    input wire [2:0] core_state,
    input wire [15:0] instruction,
    
    // Decoded instruction fields
    output wire [3:0] decoded_rd_address,
    output wire [3:0] decoded_rs_address,
    output wire [3:0] decoded_rt_address,
    output wire [2:0] decoded_nzp,
    output wire [7:0] decoded_immediate,
    
    // Control signals
    output wire decoded_reg_write_enable,
    output wire decoded_mem_read_enable,
    output wire decoded_mem_write_enable,
    output wire decoded_nzp_write_enable,
    output wire [2:0] decoded_reg_input_mux,
    output wire [1:0] decoded_alu_arithmetic_mux,
    output wire decoded_alu_output_mux,
    output wire decoded_pc_mux,
    output wire decoded_fma_enable,
    output wire decoded_act_enable,
    output wire [1:0] decoded_act_func,
    output wire decoded_ret
);

    // Instantiate the Decoder
    decoder decoder_inst (
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

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/decoder.vcd");
        $dumpvars(0, tb_decoder);
    end

endmodule

