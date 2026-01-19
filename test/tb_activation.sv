`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for Activation Unit
// Provides direct access to Activation signals for cocotb testing
module tb_activation #(
    parameter DATA_BITS = 16  // Q1.15 fixed-point width
) (
    input wire clk,
    input wire reset,
    input wire enable,
    
    // Control inputs
    input wire [2:0] core_state,
    input wire activation_enable,
    input wire [1:0] activation_func,  // 00=none, 01=ReLU, 10=LeakyReLU, 11=ClippedReLU
    
    // Data inputs
    input wire [DATA_BITS-1:0] unbiased_activation,  // Input from FMA
    input wire [DATA_BITS-1:0] bias,                  // Bias value
    
    // Output
    output wire [DATA_BITS-1:0] activation_out
);

    // Instantiate the Activation unit
    activation #(
        .DATA_BITS(DATA_BITS)
    ) activation_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .activation_enable(activation_enable),
        .activation_func(activation_func),
        .unbiased_activation(unbiased_activation),
        .bias(bias),
        .activation_out(activation_out)
    );

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/activation.vcd");
        $dumpvars(0, tb_activation);
    end

endmodule

