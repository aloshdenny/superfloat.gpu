`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for Systolic Array Cluster
// Tests multiple 8x8 systolic arrays with hierarchical control
module tb_systolic_array_cluster #(
    parameter DATA_BITS = 16,        // Q1.15 fixed-point width
    parameter ARRAY_SIZE = 8,        // 8x8 array size
    parameter NUM_ARRAYS = 8         // 8 arrays per cluster
) (
    input wire clk,
    input wire reset,
    input wire enable,
    
    // Array selection
    input wire [2:0] array_select,
    
    // Control signals
    input wire clear_acc,
    input wire load_weights,
    input wire compute_enable,
    input wire broadcast_mode,
    
    // Input data buses - flat arrays for cocotb access
    input wire [ARRAY_SIZE*DATA_BITS-1:0] a_inputs_flat,
    input wire [ARRAY_SIZE*DATA_BITS-1:0] b_inputs_flat,
    
    // Output data - flat array
    output wire [ARRAY_SIZE*ARRAY_SIZE*DATA_BITS-1:0] results_flat,
    
    // Status
    output wire ready,
    output wire [NUM_ARRAYS-1:0] all_ready
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

    // Instantiate the Systolic Array Cluster
    systolic_array_cluster #(
        .DATA_BITS(DATA_BITS),
        .ARRAY_SIZE(ARRAY_SIZE),
        .NUM_ARRAYS(NUM_ARRAYS)
    ) cluster_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .array_select(array_select),
        .clear_acc(clear_acc),
        .load_weights(load_weights),
        .compute_enable(compute_enable),
        .broadcast_mode(broadcast_mode),
        .a_inputs(a_inputs),
        .b_inputs(b_inputs),
        .results(results),
        .ready(ready),
        .all_ready(all_ready)
    );

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/systolic_cluster.vcd");
        $dumpvars(0, tb_systolic_array_cluster);
    end

endmodule
