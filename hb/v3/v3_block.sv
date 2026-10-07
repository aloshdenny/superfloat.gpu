`default_nettype none
`timescale 1ns/1ps

// An N x N block of v3 PEs (v3_pe.sv) for study S2. Every input and output
// is registered at the block's edge, so its timing is register to register
// and wires between PEs are counted, as inside a 128 x 128 matrix unit.
//
//   a_west[r]     activation into row r          a_east[r]    out of row r
//   w_north[c]    weight chain into column c     (w_shift / w_swap)
//   psum_north[c] partial sum into column c      psum_south[c] out of column c
//
// FMT 0: v3_pe_sf (FRAC, ACC_W); FMT 1: v3_pe_fp (IN_E/IN_M -> ACC_E/ACC_M).
// TRUNC_K / COMP: truncated product; MUL_ST: product stages; CT: carry-save
// tree multiplier (v3_pe.sv).
//
// CG = 1 gates the weight registers' clocks, one gate per row for each of
// the two weight registers. GT2N has no clock-gate cell and no latch, so a
// gate is a falling-edge flop holding the enable and an AND with the clock:
// the enable is stable while the clock is high, and the gated rising edge
// comes where the CG = 0 enable would load (cycle-identical).
//
// WAVE = 1 swaps the weights with the activation wavefront instead of all at
// once, so weight tiles stream back to back: tok_west[r] marks row r's first
// activation of a tile, is registered with it and travels east with it, and
// each PE copies its shadow weight in as that activation arrives. w_swap is
// unused. With CG the active weight's gate is per PE (its token), since the
// PEs of a row swap on successive cycles.
module v3_block #(
    parameter N     = 8,
    parameter FMT   = 0,
    parameter FRAC  = 23,
    parameter ACC_W = 32,
    parameter IN_E  = 5,
    parameter IN_M  = 10,
    parameter ACC_E = 8,
    parameter ACC_M = 23,
    parameter ALIGN_STAGE = 0,
    parameter TRUNC_K = -1,
    parameter COMP  = 0,
    parameter CG    = 0,
    parameter MUL_ST = 1,
    parameter CT    = 0,
    parameter WAVE  = 0,
    parameter IW = (FMT == 0) ? 16 : 1 + IN_E + IN_M,
    parameter CW = (FMT == 0) ? ACC_W : 1 + ACC_E + ACC_M
) (
    input  wire            clk,
    input  wire            w_shift,
    input  wire            w_swap,
    input  wire [N*IW-1:0] a_west,
    input  wire [N-1:0]    tok_west,
    input  wire [N*IW-1:0] w_north,
    input  wire [N*CW-1:0] psum_north,
    output reg  [N*IW-1:0] a_east,
    output reg  [N*CW-1:0] psum_south
);
    reg            shift_q, swap_q;
    reg [N*IW-1:0] a_q, w_q;
    reg [N*CW-1:0] p_q;
    reg [N-1:0]    tok_q;

    wire [IW-1:0] a_bus [0:N-1][0:N];     // [row][col]: into PE(row, col)
    wire          t_bus [0:N-1][0:N];     // swap token into PE(row, col) (WAVE)
    wire [IW-1:0] w_bus [0:N][0:N-1];     // [row][col]
    wire [CW-1:0] p_bus [0:N][0:N-1];

    wire [N-1:0] gclk_w, gclk_a;          // per row: weight chain, active weight

    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : g_gate
            if (CG) begin : g_on
                reg en_w_n, en_a_n;
                always @(negedge clk) begin
                    en_w_n <= shift_q;
                    en_a_n <= swap_q;
                end
                assign gclk_w[r] = clk & en_w_n;
                assign gclk_a[r] = clk & en_a_n;
            end else begin : g_off
                assign gclk_w[r] = clk;
                assign gclk_a[r] = clk;
            end
        end
        for (r = 0; r < N; r = r + 1) begin : g_west
            assign a_bus[r][0] = a_q[r*IW +: IW];
            assign t_bus[r][0] = tok_q[r];
        end
        for (c = 0; c < N; c = c + 1) begin : g_north
            assign w_bus[0][c] = w_q[c*IW +: IW];
            assign p_bus[0][c] = p_q[c*CW +: CW];
        end
        for (r = 0; r < N; r = r + 1) begin : g_row
            for (c = 0; c < N; c = c + 1) begin : g_col
                wire swp, gca;
                if (WAVE) begin : g_wave
                    assign swp = t_bus[r][c];
                    if (CG) begin : g_pe_gate
                        reg en_n;
                        always @(negedge clk) en_n <= swp;
                        assign gca = clk & en_n;
                    end else begin : g_pe_clk
                        assign gca = clk;
                    end
                end else begin : g_all
                    assign swp = swap_q;
                    assign gca = gclk_a[r];
                end
                if (FMT == 0) begin : g_sf
                    v3_pe_sf #(.FRAC(FRAC), .ACC_W(ACC_W), .TRUNC_K(TRUNC_K), .COMP(COMP), .CG(CG), .MUL_ST(MUL_ST), .CT(CT)) u_pe (
                        .clk(clk), .clk_w(gclk_w[r]), .clk_a(gca), .w_shift(shift_q), .w_swap(swp),
                        .a_in(a_bus[r][c]), .a_out(a_bus[r][c+1]),
                        .w_in(w_bus[r][c]), .w_out(w_bus[r+1][c]),
                        .psum_in(p_bus[r][c]), .psum_out(p_bus[r+1][c]), .tok_out(t_bus[r][c+1])
                    );
                end else begin : g_fp
                    v3_pe_fp #(.IN_E(IN_E), .IN_M(IN_M), .ACC_E(ACC_E), .ACC_M(ACC_M),
                               .ALIGN_STAGE(ALIGN_STAGE), .TRUNC_K(TRUNC_K), .COMP(COMP), .CG(CG),
                               .MUL_ST(MUL_ST), .CT(CT)) u_pe (
                        .clk(clk), .clk_w(gclk_w[r]), .clk_a(gca), .w_shift(shift_q), .w_swap(swp),
                        .a_in(a_bus[r][c]), .a_out(a_bus[r][c+1]),
                        .w_in(w_bus[r][c]), .w_out(w_bus[r+1][c]),
                        .psum_in(p_bus[r][c]), .psum_out(p_bus[r+1][c]), .tok_out(t_bus[r][c+1])
                    );
                end
            end
        end
    endgenerate

    integer i;
    always @(posedge clk) begin
        shift_q <= w_shift;
        swap_q  <= w_swap;
        a_q <= a_west;
        tok_q <= tok_west;
        w_q <= w_north;
        p_q <= psum_north;
        for (i = 0; i < N; i = i + 1) begin
            a_east[i*IW +: IW]     <= a_bus[i][N];
            psum_south[i*CW +: CW] <= p_bus[N][i];
        end
    end
endmodule
