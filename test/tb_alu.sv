`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for ALU Unit
// Provides direct access to ALU signals for cocotb testing
module tb_alu #(
    parameter DATA_BITS = 16  // 16-bit data width
) (
    input wire clk,
    input wire reset,
    input wire enable,
    
    // Control inputs
    input wire [2:0] core_state,
    input wire [1:0] alu_arithmetic_mux,  // ADD=00, SUB=01, MUL=10, DIV=11
    input wire alu_output_mux,            // 0=arithmetic, 1=compare (NZP)
    
    // Data inputs
    input wire [DATA_BITS-1:0] rs,
    input wire [DATA_BITS-1:0] rt,
    
    // Output
    output wire [DATA_BITS-1:0] alu_out
);

    // Instantiate the ALU unit
    alu #(
        .DATA_BITS(DATA_BITS)
    ) alu_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .decoded_alu_arithmetic_mux(alu_arithmetic_mux),
        .decoded_alu_output_mux(alu_output_mux),
        .rs(rs),
        .rt(rt),
        .alu_out(alu_out)
    );

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/alu.vcd");
        $dumpvars(0, tb_alu);
    end

endmodule

