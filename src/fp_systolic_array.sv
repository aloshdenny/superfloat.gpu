// IEEE FP16 / FP32 weight-stationary systolic array (mirrors SF systolic_array)
`default_nettype none
`timescale 1ns/1ns

module fp_systolic_array #(
    parameter DATA_BITS     = 16,
    parameter EXP_BITS      = 5,
    parameter MANT_BITS     = 10,
    parameter ARRAY_SIZE    = 2,
    parameter PIPE_INTERVAL = ARRAY_SIZE
) (
    input  wire clk,
    input  wire reset,
    input  wire enable,
    input  wire clear_acc,
    input  wire load_weights,
    input  wire compute_enable,
    input  wire [DATA_BITS*ARRAY_SIZE-1:0] a_inputs_flat,
    input  wire [DATA_BITS*ARRAY_SIZE-1:0] b_inputs_flat,
    output wire [DATA_BITS*ARRAY_SIZE*ARRAY_SIZE-1:0] results_flat,
    output wire ready
);

    reg [DATA_BITS*ARRAY_SIZE-1:0] a_reg, b_reg;
    reg [ARRAY_SIZE-1:0] en_row, ce_row, ca_row, lw_row;
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
            a_reg <= a_inputs_flat;
            b_reg <= b_inputs_flat;
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                en_row[i] <= enable;
                ce_row[i] <= compute_enable;
                ca_row[i] <= clear_acc;
                lw_row[i] <= load_weights;
            end
        end
    end

    wire [DATA_BITS-1:0] a_wire [ARRAY_SIZE-1:0][ARRAY_SIZE:0];
    wire [DATA_BITS-1:0] b_wire [ARRAY_SIZE:0][ARRAY_SIZE-1:0];
    wire [DATA_BITS-1:0] results[ARRAY_SIZE-1:0][ARRAY_SIZE-1:0];

    genvar row, col;
    generate
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : g_a_in
            assign a_wire[row][0] = a_reg[(row+1)*DATA_BITS-1 -: DATA_BITS];
        end
        for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : g_b_in
            assign b_wire[0][col] = b_reg[(col+1)*DATA_BITS-1 -: DATA_BITS];
        end
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : g_flat_r
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : g_flat_c
                assign results_flat[(row*ARRAY_SIZE+col+1)*DATA_BITS-1 -: DATA_BITS]
                    = results[row][col];
            end
        end
        for (row = 0; row < ARRAY_SIZE; row = row + 1) begin : g_row
            for (col = 0; col < ARRAY_SIZE; col = col + 1) begin : g_col
                wire [DATA_BITS-1:0] a_pe_out, b_pe_out;

                ieee_fma_pe #(
                    .EXP_BITS (EXP_BITS),
                    .MANT_BITS(MANT_BITS)
                ) pe (
                    .clk(clk), .reset(reset), .enable(en_row[row]),
                    .clear_acc(ca_row[row]), .load_weight(lw_row[row]),
                    .compute_enable(ce_row[row]),
                    .a_in(a_wire[row][col]), .b_in(b_wire[row][col]),
                    .a_out(a_pe_out), .b_out(b_pe_out),
                    .acc_out(results[row][col])
                );

                if ((col + 1) < ARRAY_SIZE && ((col + 1) % PIPE_INTERVAL) == 0) begin : g_a_pipe
                    reg [DATA_BITS-1:0] a_preg;
                    always @(posedge clk) begin
                        if (reset) a_preg <= '0;
                        else if (en_row[row]) a_preg <= a_pe_out;
                    end
                    assign a_wire[row][col+1] = a_preg;
                end else begin : g_a_direct
                    assign a_wire[row][col+1] = a_pe_out;
                end

                if ((row + 1) < ARRAY_SIZE && ((row + 1) % PIPE_INTERVAL) == 0) begin : g_b_pipe
                    reg [DATA_BITS-1:0] b_preg;
                    always @(posedge clk) begin
                        if (reset) b_preg <= '0;
                        else if (en_row[row]) b_preg <= b_pe_out;
                    end
                    assign b_wire[row+1][col] = b_preg;
                end else begin : g_b_direct
                    assign b_wire[row+1][col] = b_pe_out;
                end
            end
        end
    endgenerate

    assign ready = ~ce_row[0];
endmodule

module fp16_systolic_array (
    input  wire clk, reset, enable, clear_acc, load_weights, compute_enable,
    input  wire [31:0] a_inputs_flat,
    input  wire [31:0] b_inputs_flat,
    output wire [63:0] results_flat,
    output wire ready
);
    fp_systolic_array #(.DATA_BITS(16), .EXP_BITS(5), .MANT_BITS(10), .ARRAY_SIZE(2)) u (
        .clk(clk), .reset(reset), .enable(enable), .clear_acc(clear_acc),
        .load_weights(load_weights), .compute_enable(compute_enable),
        .a_inputs_flat(a_inputs_flat), .b_inputs_flat(b_inputs_flat),
        .results_flat(results_flat), .ready(ready)
    );
endmodule

module fp32_systolic_array (
    input  wire clk, reset, enable, clear_acc, load_weights, compute_enable,
    input  wire [63:0] a_inputs_flat,
    input  wire [63:0] b_inputs_flat,
    output wire [127:0] results_flat,
    output wire ready
);
    fp_systolic_array #(.DATA_BITS(32), .EXP_BITS(8), .MANT_BITS(23), .ARRAY_SIZE(2)) u (
        .clk(clk), .reset(reset), .enable(enable), .clear_acc(clear_acc),
        .load_weights(load_weights), .compute_enable(compute_enable),
        .a_inputs_flat(a_inputs_flat), .b_inputs_flat(b_inputs_flat),
        .results_flat(results_flat), .ready(ready)
    );
endmodule
