`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for Systolic Array
// Provides direct access to array signals for cocotb testing
// Parameterized to support various array sizes (2, 4, 8, etc.)
module tb_systolic_array #(
    parameter DATA_BITS = 16,        // Q1.15 fixed-point width
    parameter ARRAY_SIZE = 4         // Default 4x4 array
) (
    input wire clk,
    input wire reset,
    input wire enable,
    
    // Control signals
    input wire clear_acc,
    input wire load_weights,
    input wire compute_enable,
    
    // Input data buses - flat arrays for cocotb access
    input wire [ARRAY_SIZE*DATA_BITS-1:0] a_inputs_flat,  // Activation inputs
    input wire [ARRAY_SIZE*DATA_BITS-1:0] b_inputs_flat,  // Weight inputs
    
    // Output data - flat array
    output wire [ARRAY_SIZE*ARRAY_SIZE*DATA_BITS-1:0] results_flat,
    
    // Status
    output wire ready
);

    // Unpack flat inputs to arrays
    wire signed [DATA_BITS-1:0] a_inputs [ARRAY_SIZE-1:0];
    wire signed [DATA_BITS-1:0] b_inputs [ARRAY_SIZE-1:0];
    wire [DATA_BITS-1:0] results [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0];
    
    genvar i, j;
    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : unpack_inputs
            assign a_inputs[i] = a_inputs_flat[i*DATA_BITS +: DATA_BITS];
            assign b_inputs[i] = b_inputs_flat[i*DATA_BITS +: DATA_BITS];
        end
        
        // Pack results to flat output
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : pack_row
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin : pack_col
                assign results_flat[(i*ARRAY_SIZE+j)*DATA_BITS +: DATA_BITS] = results[i][j];
            end
        end
    endgenerate

    // Instantiate the Systolic Array
    systolic_array #(
        .DATA_BITS(DATA_BITS),
        .ARRAY_SIZE(ARRAY_SIZE)
    ) array_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .clear_acc(clear_acc),
        .load_weights(load_weights),
        .compute_enable(compute_enable),
        .a_inputs(a_inputs),
        .b_inputs(b_inputs),
        .results(results),
        .ready(ready)
    );

    // Explicit result wires for GTKWave (avoids escaped name issues)
    wire [DATA_BITS-1:0] res_0_0 = results_flat[0*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_0_1 = results_flat[1*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_0_2 = results_flat[2*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_0_3 = results_flat[3*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_1_0 = results_flat[4*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_1_1 = results_flat[5*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_1_2 = results_flat[6*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_1_3 = results_flat[7*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_2_0 = results_flat[8*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_2_1 = results_flat[9*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_2_2 = results_flat[10*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_2_3 = results_flat[11*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_3_0 = results_flat[12*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_3_1 = results_flat[13*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_3_2 = results_flat[14*DATA_BITS +: DATA_BITS];
    wire [DATA_BITS-1:0] res_3_3 = results_flat[15*DATA_BITS +: DATA_BITS];

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
    end

endmodule

