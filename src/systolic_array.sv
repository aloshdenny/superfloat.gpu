`default_nettype none
`timescale 1ns/1ns

// SYSTOLIC ARRAY (Q1.15 Fixed-Point)
// > Configurable NxN array of processing elements for matrix multiplication
// > Weight-stationary dataflow: weights loaded once, activations flow through
// > Computes C = A × B where A, B, C are NxN matrices in Q1.15 format
// > Activation data flows west-to-east, partial results accumulate locally
// > Each PE performs MAC: acc = acc + (a * weight)
// > Weight loading: First fill propagation pipeline, then pulse load_weights
module systolic_array #(
    parameter DATA_BITS = 16,        // Q1.15 fixed-point width
    parameter ARRAY_SIZE = 4         // Configurable: 2, 4, 8, etc.
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Control signals
    input wire clear_acc,            // Clear all accumulators
    input wire load_weights,         // Load weights from b_wires into PE registers
    input wire compute_enable,       // Enable MAC computation across array

    // Input data buses (one input per row/column)
    input wire signed [DATA_BITS-1:0] a_inputs [ARRAY_SIZE-1:0],   // Activation inputs (west edge)
    input wire signed [DATA_BITS-1:0] b_inputs [ARRAY_SIZE-1:0],   // Weight inputs (north edge)

    // Output data buses (accumulated results from each PE)
    output wire [DATA_BITS-1:0] results [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0],

    // Status signals
    output wire ready                // Array ready for new computation
);
    // Internal wiring between PEs
    wire signed [DATA_BITS-1:0] a_wires [ARRAY_SIZE-1:0][ARRAY_SIZE:0];
    wire signed [DATA_BITS-1:0] b_wires [ARRAY_SIZE:0][ARRAY_SIZE-1:0];

    // Connect external inputs to array edges
    genvar row, col;
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : a_input_connect
            assign a_wires[row][0] = a_inputs[row];
        end
        for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : b_input_connect
            assign b_wires[0][col] = b_inputs[col];
        end
    endgenerate

    // Instantiate NxN array of processing elements
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : pe_rows
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : pe_cols
                systolic_pe #(
                    .DATA_BITS(DATA_BITS)
                ) pe_inst (
                    .clk(clk),
                    .reset(reset),
                    .enable(enable),
                    .clear_acc(clear_acc),
                    .load_weight(load_weights),
                    .compute_enable(compute_enable),
                    .a_in(a_wires[row][col]),
                    .b_in(b_wires[row][col]),
                    .a_out(a_wires[row][col+1]),
                    .b_out(b_wires[row+1][col]),
                    .acc_out(results[row][col])
                );
            end
        end
    endgenerate

    // Ready signal
    reg ready_reg;
    assign ready = ready_reg;

    always @(posedge clk) begin
        if (reset) begin
            ready_reg <= 1'b1;
        end else if (enable) begin
            ready_reg <= ~compute_enable;
        end
    end
endmodule

