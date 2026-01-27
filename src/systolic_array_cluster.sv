`default_nettype none
`timescale 1ns/1ns

// SYSTOLIC ARRAY CLUSTER (Hierarchical Design)
// > Contains multiple systolic arrays for parallel matrix operations
// > Provides unified interface to multiple 8x8 systolic arrays
// > Supports concurrent matrix multiplications across arrays
// > Hierarchical design for better physical synthesis
module systolic_array_cluster #(
    parameter DATA_BITS = 16,            // Q1.15 fixed-point width
    parameter ARRAY_SIZE = 8,            // Size of each systolic array (8x8)
    parameter NUM_ARRAYS = 8             // Number of systolic arrays per cluster
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Array selection
    input wire [$clog2(NUM_ARRAYS)-1:0] array_select,  // Which array to address

    // Control signals (broadcast to all or selected array)
    input wire clear_acc,                // Clear all accumulators
    input wire load_weights,             // Load weights from b_wires into PE registers
    input wire compute_enable,           // Enable MAC computation
    input wire broadcast_mode,           // If 1, control signals go to all arrays

    // Input data buses (one set per array, active based on array_select)
    input wire signed [DATA_BITS-1:0] a_inputs [ARRAY_SIZE-1:0],
    input wire signed [DATA_BITS-1:0] b_inputs [ARRAY_SIZE-1:0],

    // Output data (from selected array)
    output wire [DATA_BITS-1:0] results [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0],

    // Status signals
    output wire ready,                   // Selected array ready
    output wire [NUM_ARRAYS-1:0] all_ready  // Ready status of all arrays
);
    // Internal signals for each array
    wire [DATA_BITS-1:0] array_results [NUM_ARRAYS-1:0][ARRAY_SIZE-1:0][ARRAY_SIZE-1:0];
    wire [NUM_ARRAYS-1:0] array_ready;

    // Generate control signals for each array
    wire [NUM_ARRAYS-1:0] array_clear_acc;
    wire [NUM_ARRAYS-1:0] array_load_weights;
    wire [NUM_ARRAYS-1:0] array_compute_enable;
    wire [NUM_ARRAYS-1:0] array_selected;
    wire [NUM_ARRAYS-1:0] array_enable;

    reg [NUM_ARRAYS-1:0] compute_enable_d1;
    reg [NUM_ARRAYS-1:0] compute_enable_d2;

    genvar arr;
    generate
        for (arr = 0; arr < NUM_ARRAYS; arr = arr + 1) begin : array_ctrl
            assign array_selected[arr] = broadcast_mode ? 1'b1 : (array_select == arr);
            assign array_clear_acc[arr] = broadcast_mode ? clear_acc : 
                                          (array_select == arr) ? clear_acc : 1'b0;
            assign array_load_weights[arr] = broadcast_mode ? load_weights : 
                                             (array_select == arr) ? load_weights : 1'b0;
            assign array_compute_enable[arr] = broadcast_mode ? compute_enable : 
                                               (array_select == arr) ? compute_enable : 1'b0;

            // Enable stays on long enough to drain the PE pipeline after compute deasserts.
            assign array_enable[arr] = enable &&
                                       array_selected[arr] &&
                                       (array_clear_acc[arr] |
                                        array_load_weights[arr] |
                                        array_compute_enable[arr] |
                                        compute_enable_d1[arr] |
                                        compute_enable_d2[arr]);
        end
    endgenerate

    always @(posedge clk) begin
        if (reset) begin
            compute_enable_d1 <= {NUM_ARRAYS{1'b0}};
            compute_enable_d2 <= {NUM_ARRAYS{1'b0}};
        end else if (enable) begin
            compute_enable_d2 <= compute_enable_d1;
            compute_enable_d1 <= array_compute_enable;
        end
    end

    // Instantiate systolic arrays
    generate
        for (arr = 0; arr < NUM_ARRAYS; arr = arr + 1) begin : arrays
            systolic_array #(
                .DATA_BITS(DATA_BITS),
                .ARRAY_SIZE(ARRAY_SIZE)
            ) array_inst (
                .clk(clk),
                .reset(reset),
                .enable(array_enable[arr]),
                .clear_acc(array_clear_acc[arr]),
                .load_weights(array_load_weights[arr]),
                .compute_enable(array_compute_enable[arr]),
                .a_inputs(a_inputs),
                .b_inputs(b_inputs),
                .results(array_results[arr]),
                .ready(array_ready[arr])
            );
        end
    endgenerate

    // Output muxing - select results from specified array
    genvar row, col;
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : result_row
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : result_col
                assign results[row][col] = array_results[array_select][row][col];
            end
        end
    endgenerate

    // Status outputs
    assign ready = array_ready[array_select];
    assign all_ready = array_ready;

endmodule
