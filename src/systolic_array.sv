`default_nettype none
`timescale 1ns/1ns

// SYSTOLIC ARRAY (SF16 Fixed-Point) — Clean flat implementation
// > 4×4 (or NxN) weight-stationary systolic array
// > Computes C = A × B in SF16 format
// > All control signals registered at top-level to eliminate fanout violations.
//   Each FMA row receives its own registered copy — no local_reg wrappers needed.
// > PIPE_INTERVAL >= ARRAY_SIZE disables mid-array pipeline registers (default).

module systolic_array #(
    parameter DATA_BITS    = 16,
    parameter ARRAY_SIZE   = 2,
    parameter PIPE_INTERVAL = ARRAY_SIZE
) (
    input  wire clk,
    input  wire reset,
    input  wire enable,
    input  wire clear_acc,
    input  wire load_weights,
    input  wire compute_enable,
    input  wire signed [DATA_BITS*ARRAY_SIZE-1:0] a_inputs_flat,
    input  wire signed [DATA_BITS*ARRAY_SIZE-1:0] b_inputs_flat,
    output wire [DATA_BITS*ARRAY_SIZE*ARRAY_SIZE-1:0] results_flat,
    output wire ready
);

    // -----------------------------------------------------------------------
    // Input pipeline stage — register EVERY control and data input.
    // Per-row control vectors limit each register's fanout to ARRAY_SIZE
    // (not ARRAY_SIZE²), fixing setup violations on the enable net in ss/100C.
    // -----------------------------------------------------------------------
    reg signed [DATA_BITS*ARRAY_SIZE-1:0] a_reg, b_reg;

    // Per-row registered control signals (one FF per row per signal)
    reg [ARRAY_SIZE-1:0] en_row;
    reg [ARRAY_SIZE-1:0] ce_row;
    reg [ARRAY_SIZE-1:0] ca_row;
    reg [ARRAY_SIZE-1:0] lw_row;

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            a_reg  <= '0;
            b_reg  <= '0;
            en_row <= '0;
            ce_row <= '0;
            ca_row <= '0;
            lw_row <= '0;
        end else begin
            a_reg  <= a_inputs_flat;
            b_reg  <= b_inputs_flat;
            // Replicate scalar → per-row (each bit driven by its own FF)
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                en_row[i] <= enable;
                ce_row[i] <= compute_enable;
                ca_row[i] <= clear_acc;
                lw_row[i] <= load_weights;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Internal interconnect
    // -----------------------------------------------------------------------
    wire signed [DATA_BITS-1:0] a_wire [ARRAY_SIZE-1:0][ARRAY_SIZE:0];
    wire signed [DATA_BITS-1:0] b_wire [ARRAY_SIZE:0][ARRAY_SIZE-1:0];
    wire        [DATA_BITS-1:0] results[ARRAY_SIZE-1:0][ARRAY_SIZE-1:0];

    genvar row, col;

    // Connect registered inputs to array edges
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : g_a_in
            assign a_wire[row][0] = a_reg[(row+1)*DATA_BITS-1 -: DATA_BITS];
        end
        for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : g_b_in
            assign b_wire[0][col] = b_reg[(col+1)*DATA_BITS-1 -: DATA_BITS];
        end
    endgenerate

    // Flatten result array to output port
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : g_flat_r
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : g_flat_c
                assign results_flat[(row*ARRAY_SIZE+col+1)*DATA_BITS-1 -: DATA_BITS]
                    = results[row][col];
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    // FMA array
    // Each FMA is driven directly from the registered per-row control signals.
    // No local_reg wrappers — those were being merged back by Yosys anyway.
    // -----------------------------------------------------------------------
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : g_row
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : g_col

                wire signed [DATA_BITS-1:0] a_pe_out, b_pe_out;

                systolic_pe pe (
                    .clk            (clk),
                    .reset          (reset),
                    .enable         (en_row[row]),
                    .clear_acc      (ca_row[row]),
                    .load_weight    (lw_row[row]),
                    .compute_enable (ce_row[row]),
                    .a_in           (a_wire[row][col]),
                    .b_in           (b_wire[row][col]),
                    .a_out          (a_pe_out),
                    .b_out          (b_pe_out),
                    .acc_out        (results[row][col])
                );

                // Horizontal A-flow: optional pipeline register at col boundary
                if ((col + 1) < ARRAY_SIZE && ((col + 1) % PIPE_INTERVAL) == 0) begin : g_a_pipe
                    reg signed [DATA_BITS-1:0] a_preg;
                    always @(posedge clk) begin
                        if (reset)         a_preg <= '0;
                        else if (en_row[row]) a_preg <= a_pe_out;
                    end
                    assign a_wire[row][col+1] = a_preg;
                end else begin : g_a_direct
                    assign a_wire[row][col+1] = a_pe_out;
                end

                // Vertical B-flow: optional pipeline register at row boundary
                if ((row + 1) < ARRAY_SIZE && ((row + 1) % PIPE_INTERVAL) == 0) begin : g_b_pipe
                    reg signed [DATA_BITS-1:0] b_preg;
                    always @(posedge clk) begin
                        if (reset)         b_preg <= '0;
                        else if (en_row[row]) b_preg <= b_pe_out;
                    end
                    assign b_wire[row+1][col] = b_preg;
                end else begin : g_b_direct
                    assign b_wire[row+1][col] = b_pe_out;
                end

            end
        end
    endgenerate

    // ready deasserts while any FMA is computing
    assign ready = ~ce_row[0];

endmodule