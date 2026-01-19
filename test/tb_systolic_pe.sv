`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for Systolic PE (Processing Element)
// Provides direct access to PE signals for cocotb testing
module tb_systolic_pe #(
    parameter DATA_BITS = 16,  // Q1.15 fixed-point width
    parameter ACC_BITS = 24    // Accumulator width
) (
    input wire clk,
    input wire reset,
    input wire enable,
    
    // Control signals
    input wire clear_acc,
    input wire load_weight,
    input wire compute_enable,
    
    // Data inputs
    input wire [DATA_BITS-1:0] a_in,    // Activation input
    input wire [DATA_BITS-1:0] b_in,    // Weight input
    
    // Data outputs
    output wire [DATA_BITS-1:0] a_out,  // Activation passthrough
    output wire [DATA_BITS-1:0] b_out,  // Weight passthrough
    
    // Accumulator output
    output wire [DATA_BITS-1:0] acc_out
);

    // Instantiate the Systolic PE
    systolic_pe #(
        .DATA_BITS(DATA_BITS),
        .ACC_BITS(ACC_BITS)
    ) pe_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .clear_acc(clear_acc),
        .load_weight(load_weight),
        .compute_enable(compute_enable),
        .a_in(a_in),
        .b_in(b_in),
        .a_out(a_out),
        .b_out(b_out),
        .acc_out(acc_out)
    );

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/systolic_pe.vcd");
        $dumpvars(0, tb_systolic_pe);
    end

endmodule

