`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for one systolic PE. It models the PE's array context:
// inputs are canonicalised (negative zero -> +0) as the array edge does, and
// the raw two's-complement accumulator is converted to SF16 sign-magnitude as
// the core's readout does.
module tb_systolic_pe #(
    parameter DATA_BITS = 16  // Q1.15 fixed-point width
) (
    input wire clk,
    input wire reset,
    input wire enable,                  // unused: the PE runs freely
    
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

    wire [DATA_BITS-1:0] a_canon = (a_in == 16'h8000) ? 16'h0000 : a_in;
    wire [DATA_BITS-1:0] b_canon = (b_in == 16'h8000) ? 16'h0000 : b_in;
    wire signed [15:0]   acc_raw;
    assign acc_out = acc_raw[15] ? {1'b1, 15'(-acc_raw)} : acc_raw;

    systolic_pe #(
        .DATA_BITS(DATA_BITS)
    ) pe_inst (
        .clk(clk),
        .reset(reset),
        .clear_acc(clear_acc),
        .load_weight(load_weight),
        .compute_enable(compute_enable),
        .a_in(a_canon),
        .b_in(b_canon),
        .a_out(a_out),
        .b_out(b_out),
        .acc_raw(acc_raw)
    );

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/systolic_pe.vcd");
        $dumpvars(0, tb_systolic_pe);
    end

endmodule

