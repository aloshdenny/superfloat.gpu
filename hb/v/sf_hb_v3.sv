`include "bsg_manycore_defines.svh"

// SuperFloat v3 matrix tile for HammerBlade (bsg_manycore): one NA x NA
// weight-stationary array of v3 PEs (hb/v3/v3_block.sv, WAVE = 1), a DMA, an
// activation buffer, weight-tile slots, accumulators and the format's pop,
// behind a bsg_manycore_endpoint_standard. The same tile in SF16, FP16 and
// BF16: only the PE parameters and the pop differ.
//
// Sizing: a tile's network port returns at most one 32-bit word (two 16-bit
// values) per cycle. Each NA x NA weight tile is used by T activation rows,
// so the array keeps up with that port when NA^2 / 2 is about T: NA = 8 for
// GPT-2 prompts of about 32 tokens. A 128 x 128 array would sit idle.
//
// One launch computes C[T x NC] columns [8 cb, 8 cb + 8) for cb in
// [CB_START, CB_START + CB_COUNT) of C = A W, A [T x K], all in DRAM:
//   A    row-major T x K 16-bit words at A_BASE; loaded once into the
//        activation buffer (banked by k mod NA: one bank per array row)
//   W    NA x NA tiles at W_BASE, tile (cb, kb) at index cb * K/NA + kb,
//        row-major (row r = k within the block); streamed through WS slots
//   C    row-major T x NC 16-bit words at C_BASE
// Per column block the K/NA passes accumulate in the accumulators (the
// format's accumulator: SF24, FP24); the last pass's results go through the
// pop (SF16: shift right by SHIFT, round to nearest even, saturate; FP16 and
// BF16: round FP24 to nearest even, flush, overflow to infinity) and are
// stored, two values per word.
//
// Array schedule (v3/pe/check_wave.py proves it bit-exact and tight):
//   pass p shifts its tile in over NA cycles from s_p, then its first
//   activation and swap token enter row 0 at t0_p; row r runs L cycles
//   behind row r - 1. s_p >= t0_(p-1) + (NA - 1)(L + 1),
//   t0_p >= max(s_p + NA, t0_(p-1) + T, t0_(p-1) + NA L + 3).
//
// EPA map (word addresses, bit 13 set):
//   0 A_BASE  1 W_BASE  2 C_BASE  3 T  4 K  5 NC  6 CB_START  7 CB_COUNT
//   8 SHIFT (signed, SF16 pop)  9 DONE_ADDR  10 START (write)
//   11 STATUS (bit 0 busy)  12 CYCLE  13 BUSY_CYC  14 LOADS  15 STORES
//   16 FORMAT (0 SF16, 1 FP16, 2 BF16)  17 PASSES  18 WAIT_W (cycles a pass
//   waited for its weights)  19 NA  20 {P, L}
// A launch ends like the v1 tile's: every store acknowledged, then 1 stored
// to DONE_ADDR in the launching core's data memory.
module sf_hb_v3
  import bsg_manycore_pkg::*;
  #(`BSG_INV_PARAM(x_cord_width_p)
    , `BSG_INV_PARAM(y_cord_width_p)
    , `BSG_INV_PARAM(pod_x_cord_width_p)
    , `BSG_INV_PARAM(pod_y_cord_width_p)
    , `BSG_INV_PARAM(data_width_p)
    , `BSG_INV_PARAM(addr_width_p)
    , `BSG_INV_PARAM(vcache_size_p)
    , `BSG_INV_PARAM(vcache_block_size_in_words_p)
    , `BSG_INV_PARAM(vcache_sets_p)
    , `BSG_INV_PARAM(icache_block_size_in_words_p)
    , `BSG_INV_PARAM(num_tiles_x_p)
    , `BSG_INV_PARAM(num_tiles_y_p)
    , `BSG_INV_PARAM(rev_fifo_els_p)
    , `BSG_INV_PARAM(barrier_dirs_p)
    , `BSG_INV_PARAM(ipoly_hashing_p)
    // PE (v3/pe/variants.py)
    , parameter FMT = 0, FRAC = 19, ACC_W = 24, IN_E = 5, IN_M = 10, ACC_E = 8, ACC_M = 15
    , ALIGN_STAGE = 0, TRUNC_K = -1, COMP = 0, CG = 0, MUL_ST = 1, CT = 1
    // tile
    , NA = 8, T_MAX = 128, K_MAX = 3072, WS = 4
    , max_out_credits_p = 32
    , proc_fifo_els_p = 4

    , localparam x_subcord_width_lp = `BSG_SAFE_CLOG2(num_tiles_x_p)
    , y_subcord_width_lp = `BSG_SAFE_CLOG2(num_tiles_y_p)
    , barrier_lg_dirs_lp = `BSG_SAFE_CLOG2(barrier_dirs_p+1)
    , credit_counter_width_lp = `BSG_WIDTH(32)
    , link_sif_width_lp =
      `bsg_manycore_link_sif_width(addr_width_p,data_width_p,x_cord_width_p,y_cord_width_p)
  )
  (
    input clk_i
    , input reset_i

    , input  [link_sif_width_lp-1:0] link_sif_i
    , output [link_sif_width_lp-1:0] link_sif_o

    , input  barrier_data_i
    , output barrier_data_o
    , output [barrier_dirs_p-1:0]     barrier_src_r_o
    , output [barrier_lg_dirs_lp-1:0] barrier_dest_r_o

    , input [x_subcord_width_lp-1:0] my_x_i
    , input [y_subcord_width_lp-1:0] my_y_i
    , input [pod_x_cord_width_p-1:0] pod_x_i
    , input [pod_y_cord_width_p-1:0] pod_y_i
  );

  assign barrier_data_o   = 1'b0;
  assign barrier_src_r_o  = '0;
  assign barrier_dest_r_o = '0;

  localparam IW   = 16;
  localparam CW   = (FMT == 0) ? ACC_W : 1 + ACC_E + ACC_M;
  localparam L    = (FMT == 0) ? 1 : 2 + ALIGN_STAGE;        // partial-sum stages per PE
  localparam P    = MUL_ST;                                  // product stages
  localparam FCODE = (FMT == 0) ? 0 : (IN_E == 5 ? 1 : 2);
  localparam LNA  = `BSG_SAFE_CLOG2(NA);
  localparam BANK = T_MAX * K_MAX / NA;                      // words per activation bank
  localparam LB   = `BSG_SAFE_CLOG2(BANK);
  localparam LT   = `BSG_SAFE_CLOG2(T_MAX);
  localparam TPW  = NA * NA / 2;                             // words per weight tile
  localparam LTPW = `BSG_SAFE_CLOG2(TPW);
  localparam LWS  = `BSG_SAFE_CLOG2(WS);
  localparam NTAG = 32;
  localparam RING = 8;                                       // passes in flight in the array
  localparam LR   = `BSG_SAFE_CLOG2(RING);
  localparam SWAP_SAFE = (NA - 1) * (L + 1);
  localparam RAW_MIN   = NA * L + 3;
  localparam OUT_LAT   = NA * L + 3 + P;                     // t0 + t + OUT_LAT + c: result of (t, c) readable

  // ------------------------------------------------------------------ endpoint
  `declare_bsg_manycore_packet_s(addr_width_p,data_width_p,x_cord_width_p,y_cord_width_p);

  logic                               in_v_lo, in_we_lo, in_yumi_li;
  logic [data_width_p-1:0]            in_data_lo;
  logic [addr_width_p-1:0]            in_addr_lo;
  logic [x_cord_width_p-1:0]          in_src_x_lo;
  logic [y_cord_width_p-1:0]          in_src_y_lo;
  logic                               returning_v_r;
  logic [data_width_p-1:0]            returning_data_r;
  bsg_manycore_packet_s               out_packet_li;
  logic                               out_v_li, out_ready_lo;
  logic [credit_counter_width_lp-1:0] out_credits_used_lo;
  logic                               returned_v_lo;
  logic [data_width_p-1:0]            returned_data_lo;
  logic [bsg_manycore_reg_id_width_gp-1:0] returned_reg_id_lo;

  bsg_manycore_endpoint_standard #(
    .x_cord_width_p(x_cord_width_p), .y_cord_width_p(y_cord_width_p)
    ,.fifo_els_p(proc_fifo_els_p), .data_width_p(data_width_p), .addr_width_p(addr_width_p)
    ,.icache_block_size_in_words_p(icache_block_size_in_words_p)
    ,.credit_counter_width_p(credit_counter_width_lp), .rev_fifo_els_p(rev_fifo_els_p)
    ,.use_credits_for_local_fifo_p(0)
  ) endp (
    .clk_i(clk_i), .reset_i(reset_i), .link_sif_i(link_sif_i), .link_sif_o(link_sif_o)
    ,.in_v_o(in_v_lo), .in_data_o(in_data_lo), .in_mask_o(), .in_addr_o(in_addr_lo), .in_we_o(in_we_lo)
    ,.in_load_info_o(), .in_src_x_cord_o(in_src_x_lo), .in_src_y_cord_o(in_src_y_lo), .in_yumi_i(in_yumi_li)
    ,.returning_data_i(returning_data_r), .returning_v_i(returning_v_r)
    ,.out_v_i(out_v_li), .out_packet_i(out_packet_li), .out_credit_or_ready_o(out_ready_lo)
    ,.returned_data_r_o(returned_data_lo), .returned_reg_id_r_o(returned_reg_id_lo), .returned_v_r_o(returned_v_lo)
    ,.returned_pkt_type_r_o(), .returned_yumi_i(returned_v_lo), .returned_fifo_full_o()
    ,.returned_credit_v_r_o(), .returned_credit_reg_id_r_o()
    ,.out_credits_used_o(out_credits_used_lo)
    ,.global_x_i({pod_x_i, my_x_i}), .global_y_i({pod_y_i, my_y_i})
  );

  // ------------------------------------------------------------------ CSRs
  logic [31:0] a_base_r, w_base_r, c_base_r, t_r, k_r, nc_r, cb_start_r, cb_count_r, shift_r, done_addr_r;
  logic [31:0] cycle_r, busy_cyc_r, loads_r, stores_r, passes_r, wait_w_r;
  logic [x_cord_width_p-1:0] caller_x_r;
  logic [y_cord_width_p-1:0] caller_y_r;

  typedef enum logic [1:0] {S_IDLE, S_RUN, S_WAKE} state_e;
  state_e state_r;
  wire busy = (state_r != S_IDLE);

  wire       is_csr   = in_addr_lo[13] & (in_addr_lo[addr_width_p-1:14] == '0);
  wire [4:0] csr_sel  = in_addr_lo[4:0];
  wire       csr_wr   = in_v_lo & in_we_lo & is_csr;
  wire       start_wr = csr_wr & (csr_sel == 5'd10);
  assign in_yumi_li = in_v_lo;

  logic [31:0] csr_rdata;
  always_comb begin
    csr_rdata = '0;
    if (is_csr) case (csr_sel)
      5'd0: csr_rdata = a_base_r;   5'd1: csr_rdata = w_base_r;   5'd2: csr_rdata = c_base_r;
      5'd3: csr_rdata = t_r;        5'd4: csr_rdata = k_r;        5'd5: csr_rdata = nc_r;
      5'd6: csr_rdata = cb_start_r; 5'd7: csr_rdata = cb_count_r; 5'd8: csr_rdata = shift_r;
      5'd9: csr_rdata = done_addr_r;
      5'd11: csr_rdata = {31'b0, busy};
      5'd12: csr_rdata = cycle_r;   5'd13: csr_rdata = busy_cyc_r;
      5'd14: csr_rdata = loads_r;   5'd15: csr_rdata = stores_r;
      5'd16: csr_rdata = FCODE;     5'd17: csr_rdata = passes_r;  5'd18: csr_rdata = wait_w_r;
      5'd19: csr_rdata = NA;        5'd20: csr_rdata = {16'(P), 16'(L)};
      default: csr_rdata = '0;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      returning_v_r <= 1'b0;
      {a_base_r, w_base_r, c_base_r, t_r, k_r, nc_r, cb_start_r, cb_count_r, shift_r, done_addr_r} <= '0;
    end else begin
      returning_v_r <= in_v_lo;
      returning_data_r <= in_we_lo ? '0 : csr_rdata;
      if (csr_wr & ~busy) case (csr_sel)
        5'd0: a_base_r <= in_data_lo;   5'd1: w_base_r <= in_data_lo;   5'd2: c_base_r <= in_data_lo;
        5'd3: t_r <= in_data_lo;        5'd4: k_r <= in_data_lo;        5'd5: nc_r <= in_data_lo;
        5'd6: cb_start_r <= in_data_lo; 5'd7: cb_count_r <= in_data_lo; 5'd8: shift_r <= in_data_lo;
        5'd9: done_addr_r <= in_data_lo;
        default: ;
      endcase
    end
  end

  // ------------------------------------------------------------------ launch geometry
  wire [31:0] kb_n     = k_r >> LNA;                 // passes per column block
  wire [31:0] a_words  = (t_r * k_r) >> 1;
  wire [31:0] tiles_n  = cb_count_r * kb_n;          // passes in this launch

  // ------------------------------------------------------------------ buffers
  // Activation banks: bank r holds A[t][k] for k mod NA = r, at t * K/NA + k / NA.
  logic [IW-1:0] abank [NA][BANK];
  // Weight slots: row r of a tile, NA values.
  logic [IW-1:0] wslot [WS][NA][NA];
  logic [LTPW:0] wrcv  [WS];                         // words received per slot
  // Accumulators: one memory per column.
  logic [CW-1:0] accm  [NA][T_MAX];

  // ------------------------------------------------------------------ DMA: tags
  typedef struct packed {
    logic          is_w;
    logic [LB-1:0] baddr;      // A: bank address
    logic [LNA-1:0] bank;      // A: first of two banks (even)
    logic [LWS-1:0] slot;      // W: slot
    logic [LTPW-1:0] word;     // W: word in the tile
  } tag_s;
  tag_s          tagt [NTAG];
  logic [NTAG-1:0] tag_busy_r;
  logic [4:0]    tag_free;
  logic          tag_avail;
  always_comb begin
    tag_free = '0; tag_avail = 1'b0;
    for (int i = NTAG - 1; i >= 0; i--) if (!tag_busy_r[i]) begin tag_free = 5'(i); tag_avail = 1'b1; end
  end

  // A requests walk (t, k) in steps of two values.
  logic [31:0] a_req_r, a_rcv_r;
  logic [LB-1:0] a_baddr_r;                          // t * K/NA + k / NA
  logic [LNA-1:0] a_bank_r;                          // k mod NA
  // W requests: tile index and word.
  logic [31:0] w_req_tile_r, tiles_shifted_r;
  logic [LTPW-1:0] w_req_word_r;

  // Stores: one FIFO per column pair, filled by the pop, drained here.
  localparam NP = NA / 2;
  localparam SFD = T_MAX;
  localparam LSF = `BSG_SAFE_CLOG2(SFD);
  logic [63:0] sfifo [NP][SFD];                      // {EVA, data}
  logic [LSF:0] sf_wp [NP], sf_rp [NP];
  logic [LSF:0] sf_cnt [NP];
  logic [NP-1:0] sf_nonempty;
  logic [$clog2(NP)-1:0] sf_pick;
  always_comb begin
    sf_pick = '0;
    for (int i = 0; i < NP; i++) begin
      sf_cnt[i] = sf_wp[i] - sf_rp[i];
      sf_nonempty[i] = (sf_cnt[i] != 0);
    end
    for (int i = NP - 1; i >= 0; i--) if (sf_nonempty[i]) sf_pick = i[$clog2(NP)-1:0];
  end
  wire [63:0] sf_head = sfifo[sf_pick][sf_rp[sf_pick][LSF-1:0]];

  wire credit_ok = (out_credits_used_lo < credit_counter_width_lp'(max_out_credits_p));
  wire a_load_go = (state_r == S_RUN) & (a_req_r < a_words);
  wire w_load_go = (state_r == S_RUN) & ~a_load_go & (w_req_tile_r < tiles_n) & (w_req_tile_r - tiles_shifted_r < WS);
  wire store_go  = (state_r == S_RUN) & (|sf_nonempty);
  wire wake_v    = (state_r == S_WAKE);

  typedef enum logic [1:0] {R_NONE, R_STORE, R_ALOAD, R_WLOAD} req_e;
  req_e req;
  always_comb begin
    req = R_NONE;
    if (credit_ok) begin
      if (store_go) req = R_STORE;
      else if (a_load_go & tag_avail) req = R_ALOAD;
      else if (w_load_go & tag_avail) req = R_WLOAD;
    end
  end

  logic [31:0] req_eva;
  always_comb begin
    case (req)
      R_STORE: req_eva = sf_head[63:32];
      R_ALOAD: req_eva = a_base_r + (a_req_r << 2);
      default: req_eva = w_base_r + (((cb_start_r * kb_n) + w_req_tile_r) << (LTPW + 2)) + (32'(w_req_word_r) << 2);
    endcase
  end

  logic [x_cord_width_p-1:0] npa_x;
  logic [y_cord_width_p-1:0] npa_y;
  logic [addr_width_p-1:0]   npa_epa;
  logic                      npa_invalid;
  bsg_manycore_eva_to_npa #(
    .data_width_p(data_width_p), .addr_width_p(addr_width_p)
    ,.x_cord_width_p(x_cord_width_p), .y_cord_width_p(y_cord_width_p)
    ,.pod_x_cord_width_p(pod_x_cord_width_p), .pod_y_cord_width_p(pod_y_cord_width_p)
    ,.num_tiles_x_p(num_tiles_x_p), .num_tiles_y_p(num_tiles_y_p)
    ,.vcache_block_size_in_words_p(vcache_block_size_in_words_p)
    ,.vcache_size_p(vcache_size_p), .vcache_sets_p(vcache_sets_p), .ipoly_hashing_p(ipoly_hashing_p)
  ) eva2npa (
    .eva_i(req_eva), .tgo_x_i('0), .tgo_y_i('0), .pod_x_i(pod_x_i), .pod_y_i(pod_y_i)
    ,.x_cord_o(npa_x), .y_cord_o(npa_y), .epa_o(npa_epa), .is_invalid_addr_o(npa_invalid)
  );

  always_comb begin
    out_packet_li = '0;
    out_packet_li.src_x_cord = {pod_x_i, my_x_i};
    out_packet_li.src_y_cord = {pod_y_i, my_y_i};
    if (wake_v) begin
      out_packet_li.op_v2 = e_remote_store;
      out_packet_li.reg_id.store_mask_s.mask = 4'b1111;
      out_packet_li.payload = 32'd1;
      out_packet_li.addr = addr_width_p'(done_addr_r);
      out_packet_li.x_cord = caller_x_r;
      out_packet_li.y_cord = caller_y_r;
    end else if (req == R_STORE) begin
      out_packet_li.op_v2 = e_remote_store;
      out_packet_li.reg_id.store_mask_s.mask = 4'b1111;
      out_packet_li.payload = sf_head[31:0];
      out_packet_li.addr = npa_epa;
      out_packet_li.x_cord = npa_x;
      out_packet_li.y_cord = npa_y;
    end else begin
      out_packet_li.op_v2 = e_remote_load;
      out_packet_li.reg_id = tag_free;
      out_packet_li.payload.load_info_s.load_info = '0;   // LW
      out_packet_li.addr = npa_epa;
      out_packet_li.x_cord = npa_x;
      out_packet_li.y_cord = npa_y;
    end
  end
  assign out_v_li = wake_v | (req != R_NONE);
  wire fire = out_v_li & out_ready_lo & ~wake_v;

  // ------------------------------------------------------------------ array and schedule
  logic [31:0] now_r;                                // cycles since START
  // Passes in flight: t0, block-relative column block, first/last of its block.
  logic [31:0]  ring_t0   [RING];
  logic [31:0]  ring_cb   [RING];
  logic [31:0]  ring_kb   [RING];
  logic         ring_first[RING];
  logic         ring_last [RING];
  logic [RING-1:0] ring_v;
  logic [LR-1:0] ring_head_r, ring_tail_r;
  logic [31:0]  retired_r;

  // Shift engine
  logic         sh_active_r;
  logic [LNA-1:0] sh_j_r;
  logic [31:0]  sh_kb_r, sh_cb_r;                    // the pass being shifted
  logic [31:0]  last_t0_r;
  logic         any_pass_r;
  wire  [LWS-1:0] sh_slot = tiles_shifted_r[LWS-1:0];
  wire          a_loaded  = (a_rcv_r == a_words);
  wire          slot_ready = (wrcv[sh_slot] == (LTPW+1)'(TPW));
  wire          pass_left  = (tiles_shifted_r < tiles_n);
  // the first shift cycle is next cycle: s_p = now + 1 >= t0_(p-1) + SWAP_SAFE
  wire          sh_time_ok = ~any_pass_r | (now_r + 1 >= last_t0_r + SWAP_SAFE);
  // A last pass needs room for its T results in every store FIFO.
  logic         sf_room;
  always_comb begin
    sf_room = 1'b1;
    for (int i = 0; i < NP; i++) if (32'(sf_cnt[i]) + t_r > SFD) sf_room = 1'b0;
  end
  wire          sh_is_last = (sh_kb_r == kb_n - 1);
  wire          ring_space = ~ring_v[ring_tail_r];
  wire          sh_start = (state_r == S_RUN) & ~sh_active_r & pass_left & a_loaded & slot_ready
                           & sh_time_ok & ring_space & (~sh_is_last | sf_room);
  wire          sh_waiting = (state_r == S_RUN) & ~sh_active_r & pass_left & a_loaded & sh_time_ok & ~slot_ready;

  logic [NA*IW-1:0] blk_w_north, blk_a_west;
  logic [NA-1:0]    blk_tok_west;
  logic [NA*CW-1:0] blk_psum_north, blk_psum_south;
  logic             blk_w_shift;

  // Weight row NA-1-j of the slot during shift cycle j.
  always_comb begin
    blk_w_shift = sh_active_r;
    for (int c = 0; c < NA; c++)
      blk_w_north[c*IW +: IW] = sh_active_r ? wslot[sh_slot][NA-1-sh_j_r][c] : '0;
  end

  // Activations and tokens: row r of the pass with now in [t0 + r L, t0 + r L + T).
  always_comb begin
    blk_a_west = '0;
    blk_tok_west = '0;
    for (int r = 0; r < NA; r++)
      for (int e = 0; e < RING; e++)
        if (ring_v[e] && now_r >= ring_t0[e] + 32'(r * L) && now_r < ring_t0[e] + 32'(r * L) + t_r) begin
          automatic logic [31:0] t = now_r - ring_t0[e] - 32'(r * L);
          blk_a_west[r*IW +: IW] = abank[r][LB'(t * kb_n + ring_kb[e])];
          blk_tok_west[r] = (t == 0);
        end
  end

  // Partial sums in: column c of the pass with now in [t0 + 1 + P + c, + T).
  always_comb begin
    blk_psum_north = '0;
    for (int c = 0; c < NA; c++)
      for (int e = 0; e < RING; e++)
        if (ring_v[e] && !ring_first[e] && now_r >= ring_t0[e] + 32'(1 + P + c)
            && now_r < ring_t0[e] + 32'(1 + P + c) + t_r)
          blk_psum_north[c*CW +: CW] = accm[c][LT'(now_r - ring_t0[e] - 32'(1 + P + c))];
  end

  v3_block #(
    .N(NA), .FMT(FMT), .FRAC(FRAC), .ACC_W(ACC_W), .IN_E(IN_E), .IN_M(IN_M), .ACC_E(ACC_E), .ACC_M(ACC_M)
    ,.ALIGN_STAGE(ALIGN_STAGE), .TRUNC_K(TRUNC_K), .COMP(COMP), .CG(CG), .MUL_ST(MUL_ST), .CT(CT), .WAVE(1)
  ) mxu (
    .clk(clk_i), .w_shift(blk_w_shift), .w_swap(1'b0), .a_west(blk_a_west), .tok_west(blk_tok_west)
    ,.w_north(blk_w_north), .psum_north(blk_psum_north), .a_east(), .psum_south(blk_psum_south)
  );

  // ------------------------------------------------------------------ pop
  function automatic logic [15:0] pop_sf(input logic [CW-1:0] acc, input logic signed [31:0] sh);
    logic        s;
    logic [63:0] mag, q, rest, half;
    s   = acc[CW-1];
    mag = s ? 64'(-$signed({{(64-CW){acc[CW-1]}}, acc})) : 64'(acc);
    if (sh > 0) begin
      if (sh >= 63) q = 0;
      else begin
        q    = mag >> sh;
        rest = mag & ((64'd1 << sh) - 1);
        half = 64'd1 << (sh - 1);
        if (rest > half || (rest == half && q[0])) q = q + 1;
      end
    end else begin
      q = (-sh >= 40) ? (mag != 0 ? 64'hFFFF : 0) : (mag << (-sh));
    end
    if (q > 64'd32767) q = 64'd32767;
    return (q == 0) ? 16'h0000 : {s, q[14:0]};
  endfunction

  // FP24 (1/8/ACC_M) to the 16-bit format (1/IN_E/IN_M): round to nearest
  // even, flush below the smallest normal, overflow to infinity.
  function automatic logic [15:0] pop_fp(input logic [CW-1:0] acc);
    logic        s;
    logic [7:0]  e;
    logic [ACC_M-1:0] m;
    logic [IN_M:0] mr;
    logic        g, st, up;
    int          E, emin, emax;
    s = acc[CW-1]; e = acc[ACC_M +: 8]; m = acc[ACC_M-1:0];
    emin = 1 - ((1 << (IN_E - 1)) - 1);
    emax = (1 << (IN_E - 1)) - 1;
    if (e == 8'hFF) return (m != 0) ? {1'b0, {IN_E{1'b1}}, 1'b1, {(IN_M-1){1'b0}}} : {s, {IN_E{1'b1}}, {IN_M{1'b0}}};
    if (e == 0) return {s, 15'b0};
    E = int'(e) - 127;
    if (E < emin) return {s, 15'b0};
    mr = {1'b0, m[ACC_M-1 -: IN_M]};
    g  = m[ACC_M-1-IN_M];
    st = |(m & ((ACC_M)'(1 << (ACC_M-1-IN_M)) - 1));
    up = g & (st | mr[0]);
    mr = mr + up;
    if (mr[IN_M]) begin E = E + 1; mr = '0; end
    if (E > emax) return {s, {IN_E{1'b1}}, {IN_M{1'b0}}};
    return {s, IN_E'(E + emax), mr[IN_M-1:0]};
  endfunction

  // Results out of column c: the pass with now in [t0 + OUT_LAT + c, + T).
  logic [NA-1:0]    res_v;
  logic [LT-1:0]    res_t  [NA];
  logic [31:0]      res_e  [NA];
  logic [NA-1:0]    res_last;
  always_comb begin
    res_v = '0; res_last = '0;
    for (int c = 0; c < NA; c++) begin
      res_t[c] = '0; res_e[c] = '0;
      for (int e = 0; e < RING; e++)
        if (ring_v[e] && now_r >= ring_t0[e] + 32'(OUT_LAT + c) && now_r < ring_t0[e] + 32'(OUT_LAT + c) + t_r) begin
          res_v[c] = 1'b1;
          res_t[c] = LT'(now_r - ring_t0[e] - 32'(OUT_LAT + c));
          res_e[c] = 32'(e);
          res_last[c] = ring_last[e];
        end
    end
  end
  logic [15:0] popped [NA];
  always_comb
    for (int c = 0; c < NA; c++)
      popped[c] = (FMT == 0) ? pop_sf(blk_psum_south[c*CW +: CW], $signed(shift_r))
                             : pop_fp(blk_psum_south[c*CW +: CW]);
  logic [15:0] hold [NP];

  // ------------------------------------------------------------------ sequential
  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      state_r <= S_IDLE;
      cycle_r <= '0; busy_cyc_r <= '0; loads_r <= '0; stores_r <= '0; passes_r <= '0; wait_w_r <= '0;
      tag_busy_r <= '0;
      ring_v <= '0; ring_head_r <= '0; ring_tail_r <= '0;
      sh_active_r <= 1'b0;
      for (int i = 0; i < NP; i++) begin sf_wp[i] <= '0; sf_rp[i] <= '0; end
      for (int s = 0; s < WS; s++) wrcv[s] <= '0;
    end else begin
      cycle_r <= cycle_r + 1;
      if (busy) busy_cyc_r <= busy_cyc_r + 1;
      now_r <= now_r + 1;

      case (state_r)
        S_IDLE: if (start_wr) begin
          caller_x_r <= in_src_x_lo;
          caller_y_r <= in_src_y_lo;
          state_r <= S_RUN;
          now_r <= '0;
          a_req_r <= '0; a_rcv_r <= '0; a_baddr_r <= '0; a_bank_r <= '0;
          w_req_tile_r <= '0; w_req_word_r <= '0; tiles_shifted_r <= '0;
          retired_r <= '0; any_pass_r <= 1'b0; sh_kb_r <= '0; sh_cb_r <= '0;
          for (int s = 0; s < WS; s++) wrcv[s] <= '0;
        end
        S_RUN: if (retired_r == tiles_n && ~|sf_nonempty && out_credits_used_lo == '0 && tag_busy_r == '0)
          state_r <= S_WAKE;
        S_WAKE: if (out_ready_lo) state_r <= S_IDLE;
        default: state_r <= S_IDLE;
      endcase

      // ---- requests
      if (fire) begin
        case (req)
          R_STORE: begin
            sf_rp[sf_pick] <= sf_rp[sf_pick] + 1;
            stores_r <= stores_r + 1;
          end
          R_ALOAD: begin
            tag_busy_r[tag_free] <= 1'b1;
            tagt[tag_free] <= '{is_w: 1'b0, baddr: a_baddr_r, bank: a_bank_r, slot: '0, word: '0};
            a_req_r <= a_req_r + 1;
            loads_r <= loads_r + 1;
            // next pair: k += 2; past the row's end, the next row
            if (a_bank_r == LNA'(NA - 2)) begin a_bank_r <= '0; a_baddr_r <= a_baddr_r + 1; end
            else a_bank_r <= a_bank_r + 2;
          end
          R_WLOAD: begin
            tag_busy_r[tag_free] <= 1'b1;
            tagt[tag_free] <= '{is_w: 1'b1, baddr: '0, bank: '0, slot: w_req_tile_r[LWS-1:0], word: w_req_word_r};
            loads_r <= loads_r + 1;
            if (w_req_word_r == LTPW'(TPW - 1)) begin
              w_req_word_r <= '0;
              w_req_tile_r <= w_req_tile_r + 1;
            end else w_req_word_r <= w_req_word_r + 1;
          end
          default: ;
        endcase
      end

      // ---- returned loads
      if (returned_v_lo) begin
        automatic tag_s tg = tagt[returned_reg_id_lo];
        tag_busy_r[returned_reg_id_lo] <= 1'b0;
        if (!tg.is_w) begin
          abank[tg.bank][tg.baddr]     <= returned_data_lo[15:0];
          abank[tg.bank + 1][tg.baddr] <= returned_data_lo[31:16];
          a_rcv_r <= a_rcv_r + 1;
        end else begin
          wslot[tg.slot][tg.word >> (LNA - 1)][(tg.word << 1) % NA]     <= returned_data_lo[15:0];
          wslot[tg.slot][tg.word >> (LNA - 1)][(tg.word << 1) % NA + 1] <= returned_data_lo[31:16];
        end
      end
      // per-slot receive counts (a slot is reset when its tile is shifted in)
      for (int s = 0; s < WS; s++) begin
        automatic logic inc = returned_v_lo && tagt[returned_reg_id_lo].is_w && tagt[returned_reg_id_lo].slot == LWS'(s);
        automatic logic clr = sh_active_r && sh_j_r == LNA'(NA - 1) && sh_slot == LWS'(s);
        if (clr) wrcv[s] <= inc ? 1 : 0;
        else if (inc) wrcv[s] <= wrcv[s] + 1;
      end

      // ---- shift engine and pass launch
      if (sh_waiting) wait_w_r <= wait_w_r + 1;
      if (sh_start) begin
        sh_active_r <= 1'b1;
        sh_j_r <= '0;
      end else if (sh_active_r) begin
        if (sh_j_r == LNA'(NA - 1)) begin
          automatic logic [31:0] t0 = now_r + 1;
          if (any_pass_r) begin
            if (last_t0_r + t_r > t0) t0 = last_t0_r + t_r;
            if (last_t0_r + RAW_MIN > t0) t0 = last_t0_r + RAW_MIN;
          end
          sh_active_r <= 1'b0;
          ring_v[ring_tail_r]     <= 1'b1;
          ring_t0[ring_tail_r]    <= t0;
          ring_cb[ring_tail_r]    <= sh_cb_r;
          ring_kb[ring_tail_r]    <= sh_kb_r;
          ring_first[ring_tail_r] <= (sh_kb_r == 0);
          ring_last[ring_tail_r]  <= (sh_kb_r == kb_n - 1);
          ring_tail_r <= ring_tail_r + 1;
          last_t0_r <= t0;
          any_pass_r <= 1'b1;
          tiles_shifted_r <= tiles_shifted_r + 1;
          passes_r <= passes_r + 1;
          if (sh_kb_r == kb_n - 1) begin sh_kb_r <= '0; sh_cb_r <= sh_cb_r + 1; end
          else sh_kb_r <= sh_kb_r + 1;
        end else sh_j_r <= sh_j_r + 1;
      end

      // ---- retire passes whose last result has left
      if (ring_v[ring_head_r] && now_r >= ring_t0[ring_head_r] + t_r + 32'(OUT_LAT + NA)) begin
        ring_v[ring_head_r] <= 1'b0;
        ring_head_r <= ring_head_r + 1;
        retired_r <= retired_r + 1;
      end

      // ---- results: accumulate, or pop and stage two per word
      for (int c = 0; c < NA; c++) if (res_v[c]) begin
        if (!res_last[c]) accm[c][res_t[c]] <= blk_psum_south[c*CW +: CW];
        else if (c % 2 == 0) hold[c/2] <= popped[c];
        else begin
          automatic logic [31:0] col = (cb_start_r + ring_cb[res_e[c]]) * NA + 32'(c - 1);
          automatic logic [31:0] eva = c_base_r + ((32'(res_t[c]) * nc_r + col) << 1);
          sfifo[c/2][sf_wp[c/2][LSF-1:0]] <= {eva, popped[c], hold[c/2]};
          sf_wp[c/2] <= sf_wp[c/2] + 1;
        end
      end
    end
  end

  // synopsys translate_off
  initial $display("## sf_hb_v3: SuperFloat v3 matrix tile %0dx%0d, format %0d, L %0d, P %0d, at %m", NA, NA, FCODE, L, P);
  always_ff @(negedge clk_i) if (~reset_i) begin
    if ((req != R_NONE) & npa_invalid & fire)
      $error("[sf_hb_v3] invalid EVA %h", req_eva);
    if (start_wr & busy) $error("[sf_hb_v3] START while busy");
    if (state_r == S_IDLE && start_wr && (t_r > T_MAX || k_r > K_MAX || k_r % NA != 0 || nc_r % NA != 0))
      $error("[sf_hb_v3] launch out of range: T %0d K %0d NC %0d", t_r, k_r, nc_r);
    if (returned_v_lo && !tag_busy_r[returned_reg_id_lo]) $error("[sf_hb_v3] load returned to a free tag");
    for (int i = 0; i < NP; i++) if (sf_cnt[i] > SFD) $error("[sf_hb_v3] store FIFO overflow");
  end
  // synopsys translate_on

endmodule

// One module per format and product depth, with the parameters the hetero
// socket passes (unused ones accepted and dropped). PE parameters are each
// format's lever variant (v3/pe/variants.py) with the carry-save multiplier
// (CT): sf16_sf24_tgc, fp16_fp24_a_tgc, bf16_fp24_a_gc; MS = product stages
// (MUL_ST): 1 for those, 2 for the *c2 variants.
`define SF_HB_V3_FORMAT(NAME, PE_PARAMS)                                       \
module NAME                                                                   \
  import bsg_manycore_pkg::*;                                                 \
  #(`BSG_INV_PARAM(x_cord_width_p), `BSG_INV_PARAM(y_cord_width_p)            \
    , `BSG_INV_PARAM(pod_x_cord_width_p), `BSG_INV_PARAM(pod_y_cord_width_p)  \
    , `BSG_INV_PARAM(data_width_p), `BSG_INV_PARAM(addr_width_p)              \
    , `BSG_INV_PARAM(dmem_size_p), `BSG_INV_PARAM(vcache_size_p)              \
    , `BSG_INV_PARAM(vcache_block_size_in_words_p), `BSG_INV_PARAM(vcache_sets_p) \
    , `BSG_INV_PARAM(icache_entries_p), `BSG_INV_PARAM(icache_tag_width_p)    \
    , `BSG_INV_PARAM(icache_block_size_in_words_p)                            \
    , `BSG_INV_PARAM(num_tiles_x_p), `BSG_INV_PARAM(num_tiles_y_p)            \
    , `BSG_INV_PARAM(fwd_fifo_els_p), `BSG_INV_PARAM(rev_fifo_els_p)          \
    , `BSG_INV_PARAM(barrier_dirs_p), `BSG_INV_PARAM(ipoly_hashing_p)         \
    , debug_p = 0                                                             \
    , localparam x_subcord_width_lp = `BSG_SAFE_CLOG2(num_tiles_x_p)          \
    , y_subcord_width_lp = `BSG_SAFE_CLOG2(num_tiles_y_p)                     \
    , barrier_lg_dirs_lp = `BSG_SAFE_CLOG2(barrier_dirs_p+1)                  \
    , link_sif_width_lp =                                                     \
      `bsg_manycore_link_sif_width(addr_width_p,data_width_p,x_cord_width_p,y_cord_width_p) \
  ) (                                                                         \
    input clk_i, input reset_i                                                \
    , input [link_sif_width_lp-1:0] link_sif_i                                \
    , output [link_sif_width_lp-1:0] link_sif_o                               \
    , input barrier_data_i, output barrier_data_o                             \
    , output [barrier_dirs_p-1:0] barrier_src_r_o                             \
    , output [barrier_lg_dirs_lp-1:0] barrier_dest_r_o                        \
    , input [x_subcord_width_lp-1:0] my_x_i, input [y_subcord_width_lp-1:0] my_y_i \
    , input [pod_x_cord_width_p-1:0] pod_x_i, input [pod_y_cord_width_p-1:0] pod_y_i \
  );                                                                          \
  sf_hb_v3 #(.x_cord_width_p(x_cord_width_p), .y_cord_width_p(y_cord_width_p) \
    , .pod_x_cord_width_p(pod_x_cord_width_p), .pod_y_cord_width_p(pod_y_cord_width_p) \
    , .data_width_p(data_width_p), .addr_width_p(addr_width_p)                \
    , .vcache_size_p(vcache_size_p)                                           \
    , .vcache_block_size_in_words_p(vcache_block_size_in_words_p)             \
    , .vcache_sets_p(vcache_sets_p)                                           \
    , .icache_block_size_in_words_p(icache_block_size_in_words_p)             \
    , .num_tiles_x_p(num_tiles_x_p), .num_tiles_y_p(num_tiles_y_p)            \
    , .rev_fifo_els_p(rev_fifo_els_p)                                         \
    , .barrier_dirs_p(barrier_dirs_p), .ipoly_hashing_p(ipoly_hashing_p)      \
    , PE_PARAMS) a (.*);                                                      \
endmodule

`define SF16_PE(MS) .FMT(0), .FRAC(19), .ACC_W(24), .TRUNC_K(9), .COMP(1024), .CG(1), .MUL_ST(MS)
`define FP16_PE(MS) .FMT(1), .IN_E(5), .IN_M(10), .ACC_E(8), .ACC_M(15), .ALIGN_STAGE(1), .TRUNC_K(4), .COMP(12), .CG(1), .MUL_ST(MS)
`define BF16_PE(MS) .FMT(1), .IN_E(8), .IN_M(7), .ACC_E(8), .ACC_M(15), .ALIGN_STAGE(1), .CG(1), .MUL_ST(MS)

`SF_HB_V3_FORMAT(sf_hb_v3_sf16, `SF16_PE(1))
`SF_HB_V3_FORMAT(sf_hb_v3_fp16, `FP16_PE(1))
`SF_HB_V3_FORMAT(sf_hb_v3_bf16, `BF16_PE(1))
`SF_HB_V3_FORMAT(sf_hb_v3_sf16_m2, `SF16_PE(2))
`SF_HB_V3_FORMAT(sf_hb_v3_fp16_m2, `FP16_PE(2))
`SF_HB_V3_FORMAT(sf_hb_v3_bf16_m2, `BF16_PE(2))
// 4 x 4 arrays: the size the measured weight bandwidth keeps busy at 32 tokens
`define SF16_A4 `SF16_PE(1), .NA(4)
`define FP16_A4 `FP16_PE(1), .NA(4)
`define BF16_A4 `BF16_PE(1), .NA(4)
`SF_HB_V3_FORMAT(sf_hb_v3_sf16_a4, `SF16_A4)
`SF_HB_V3_FORMAT(sf_hb_v3_fp16_a4, `FP16_A4)
`SF_HB_V3_FORMAT(sf_hb_v3_bf16_a4, `BF16_A4)
// The configurations measured at GT2N (v3/pe variants *c2_w): carry-save
// multiplier over two product stages, wavefront swap; 8 x 8 and 4 x 4.
`define SF16_M2A8 `SF16_PE(2)
`define FP16_M2A8 `FP16_PE(2)
`define BF16_M2A8 `BF16_PE(2)
`define SF16_M2A4 `SF16_PE(2), .NA(4)
`define FP16_M2A4 `FP16_PE(2), .NA(4)
`define BF16_M2A4 `BF16_PE(2), .NA(4)
`SF_HB_V3_FORMAT(sf_hb_v3_sf16_m2a4, `SF16_M2A4)
`SF_HB_V3_FORMAT(sf_hb_v3_fp16_m2a4, `FP16_M2A4)
`SF_HB_V3_FORMAT(sf_hb_v3_bf16_m2a4, `BF16_M2A4)
