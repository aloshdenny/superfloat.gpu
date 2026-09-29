`default_nettype none
`timescale 1ns/1ns

// SYSTOLIC ARRAY (SF16 fixed point, FP16 or BF16), weight-stationary
// > One ARRAY_SIZE x ARRAY_SIZE array per core tile (8x8 on OpenFrame).
// > NUMBER_FORMAT: 0 = SF16 (systolic_pe), 1 = FP16, 2 = BF16 (fp_systolic_pe).
// > SF16 only: negative zero is canonicalised once at the array edges;
//   interior PEs only see values already cleaned by their neighbours.
// > Weights shift down one row per load_weights pulse (load rows N-1 .. 0).
// > Activations and the MAC pipeline run freely; accumulators move only on
//   compute (valid) or clear.
// > SF16: results_flat carries raw two's-complement accumulators; the reader
//   converts the one cell it selects to SF16 sign-magnitude. FP16/BF16:
//   results_flat carries the accumulators as they are.
// > All control inputs are registered once, one copy per row.
// > PIPE_INTERVAL >= ARRAY_SIZE disables mid-array pipeline registers (default).

module systolic_array #(
    parameter DATA_BITS    = 16,
    parameter ARRAY_SIZE   = 4,
    parameter PIPE_INTERVAL = ARRAY_SIZE,
    parameter NUMBER_FORMAT = 0             // 0 SF16, 1 FP16, 2 BF16
) (
    input  wire clk,
    input  wire reset,
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

    // SF16 negative zero (0x8000) is canonicalised to +0 on entry. In FP16 and
    // BF16 it is a distinct value and passes through.
    function automatic [DATA_BITS-1:0] canon(input [DATA_BITS-1:0] x);
        canon = (NUMBER_FORMAT == 0 && x == {1'b1, {(DATA_BITS-1){1'b0}}}) ? {DATA_BITS{1'b0}} : x;
    endfunction

    // Per-row registered control signals (one FF per row per signal)
    reg [ARRAY_SIZE-1:0] ce_row;
    reg [ARRAY_SIZE-1:0] ca_row;
    reg [ARRAY_SIZE-1:0] lw_row;

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            a_reg  <= '0;
            b_reg  <= '0;
            ce_row <= '0;
            ca_row <= '0;
            lw_row <= '0;
        end else begin
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                a_reg[i*DATA_BITS +: DATA_BITS] <= canon(a_inputs_flat[i*DATA_BITS +: DATA_BITS]);
                b_reg[i*DATA_BITS +: DATA_BITS] <= canon(b_inputs_flat[i*DATA_BITS +: DATA_BITS]);
            end
            // Replicate scalar → per-row (each bit driven by its own FF)
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
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

                if (NUMBER_FORMAT == 0) begin : g_sf16
                    systolic_pe pe (
                        .clk            (clk),
                        .reset          (reset),
                        .clear_acc      (ca_row[row]),
                        .load_weight    (lw_row[row]),
                        .compute_enable (ce_row[row]),
                        .a_in           (a_wire[row][col]),
                        .b_in           (b_wire[row][col]),
                        .a_out          (a_pe_out),
                        .b_out          (b_pe_out),
                        .acc_raw        (results[row][col])
                    );
                end else begin : g_fp
                    fp_systolic_pe #(
                        .EXP_BITS       (NUMBER_FORMAT == 2 ? 8 : 5),
                        .MANT_BITS      (NUMBER_FORMAT == 2 ? 7 : 10)
                    ) pe (
                        .clk            (clk),
                        .reset          (reset),
                        .clear_acc      (ca_row[row]),
                        .load_weight    (lw_row[row]),
                        .compute_enable (ce_row[row]),
                        .a_in           (a_wire[row][col]),
                        .b_in           (b_wire[row][col]),
                        .a_out          (a_pe_out),
                        .b_out          (b_pe_out),
                        .acc            (results[row][col])
                    );
                end

                // Horizontal A-flow: optional pipeline register at col boundary
                if ((col + 1) < ARRAY_SIZE && ((col + 1) % PIPE_INTERVAL) == 0) begin : g_a_pipe
                    reg signed [DATA_BITS-1:0] a_preg;
                    always @(posedge clk) begin
                        if (reset) a_preg <= '0;
                        else       a_preg <= a_pe_out;
                    end
                    assign a_wire[row][col+1] = a_preg;
                end else begin : g_a_direct
                    assign a_wire[row][col+1] = a_pe_out;
                end

                // Vertical B-flow: optional pipeline register at row boundary
                if ((row + 1) < ARRAY_SIZE && ((row + 1) % PIPE_INTERVAL) == 0) begin : g_b_pipe
                    reg signed [DATA_BITS-1:0] b_preg;
                    always @(posedge clk) begin
                        if (reset)            b_preg <= '0;
                        else if (lw_row[row]) b_preg <= b_pe_out;
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