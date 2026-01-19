`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for FMA Unit
// Provides direct access to FMA signals for cocotb testing
module tb_fma #(
    parameter DATA_BITS = 16  // Q1.15 fixed-point width
) (
    input wire clk,
    input wire reset,
    input wire enable,
    
    // Control inputs
    input wire [2:0] core_state,
    input wire fma_enable,
    
    // Q1.15 data inputs
    input wire [DATA_BITS-1:0] rs,    // Input/Activation
    input wire [DATA_BITS-1:0] rt,    // Weight
    input wire [DATA_BITS-1:0] rq,    // Previous accumulator value
    
    // Output
    output wire [DATA_BITS-1:0] fma_out
);

    // Instantiate the FMA unit
    fma #(
        .DATA_BITS(DATA_BITS)
    ) fma_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .decoded_fma_enable(fma_enable),
        .rs(rs),
        .rt(rt),
        .rq(rq),
        .fma_out(fma_out)
    );

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/fma.vcd");
        $dumpvars(0, tb_fma);
    end

endmodule

