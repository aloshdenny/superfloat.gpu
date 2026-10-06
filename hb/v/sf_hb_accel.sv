`include "bsg_manycore_defines.svh"

// SuperFloat v1 core tile as a HammerBlade (bsg_manycore) accelerator tile.
//
// The v1 core_tile (src/core_tile.sv) runs unchanged; its modules are renamed
// sf1_* (hb/v1_prefix.py), since bsg_manycore has an alu and an lsu of its
// own. On the OpenFrame chip its program and data channels go to a shared
// instruction cache and the 16-bit pin bus; here they go to:
//   program: the chip's instruction cache (src/shared_icache.sv, one port,
//            32 entries), filled from a local 512 x 16-bit program memory
//            that the manycore writes with remote stores.
//   data:    remote loads and stores over the manycore mesh. The tile's
//            16-bit word address A is the halfword at byte EVA BASE + 2A in
//            the manycore's DRAM space; a read is a halfword remote load
//            (LHU at the vcache), a write a byte-masked remote store.
//            core_tile has one data channel, so one load is in flight at a
//            time; stores are posted (up to max_out_credits_p in flight).
//            RB_LINES > 0 adds a read buffer of whole vcache lines (see the
//            data channel section).
//
// A thread block is launched by a manycore core (the dispatcher): it writes
// BASE and DONE_ADDR, then START with the block id and thread count. The
// tile resets the core for a cycle, runs it with start high until done, waits
// for every store to be acknowledged, then stores 1 to DONE_ADDR in the
// launching core's data memory (the coordinates of the START packet).
//
// EPA map (word addresses):
//   0x0000-0x01FF  program memory, write only; data[15:0] is one instruction
//   0x2000  BASE       r/w  byte EVA of word 0 of the data window
//   0x2001  DONE_ADDR  r/w  word EPA in the launching core's data memory
//   0x2002  START      w    data[7:0] block id, data[11:8] thread count
//   0x2003  STATUS     r    bit 0 busy
//   0x2004  CYCLE      r    free-running cycle counter
//   0x2005  BUSY_CYC   r    cycles with a block running (core start high)
//   0x2006  READS      r    data words the tile read
//   0x2007  WRITES     r    data words written (remote stores)
//   0x2008  FORMAT     r    NUMBER_FORMAT (0 SF16, 1 FP16, 2 BF16)
//   0x2009  BLOCKS     r    blocks completed
//   0x200A  LOADS      r    remote loads sent (= READS without a read buffer)
//   0x200B  RB_LINES   r    read-buffer lines (0: none)
// Writes to any other address are acknowledged and ignored; reads return 0.
module sf_hb_accel
  import bsg_manycore_pkg::*;
  #(`BSG_INV_PARAM(x_cord_width_p)
    , `BSG_INV_PARAM(y_cord_width_p)
    , `BSG_INV_PARAM(pod_x_cord_width_p)
    , `BSG_INV_PARAM(pod_y_cord_width_p)
    , `BSG_INV_PARAM(data_width_p)
    , `BSG_INV_PARAM(addr_width_p)
    , `BSG_INV_PARAM(dmem_size_p)
    , `BSG_INV_PARAM(vcache_size_p)
    , `BSG_INV_PARAM(vcache_block_size_in_words_p)
    , `BSG_INV_PARAM(vcache_sets_p)
    , `BSG_INV_PARAM(icache_entries_p)
    , `BSG_INV_PARAM(icache_tag_width_p)
    , `BSG_INV_PARAM(icache_block_size_in_words_p)
    , `BSG_INV_PARAM(num_tiles_x_p)
    , `BSG_INV_PARAM(num_tiles_y_p)
    , `BSG_INV_PARAM(fwd_fifo_els_p)
    , `BSG_INV_PARAM(rev_fifo_els_p)
    , `BSG_INV_PARAM(barrier_dirs_p)
    , `BSG_INV_PARAM(ipoly_hashing_p)
    , debug_p = 0
    , parameter NUMBER_FORMAT = 0
    , RB_LINES = 0                  // read-buffer lines; 0 = one halfword load per read
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

  // This tile takes no part in the hardware barrier.
  assign barrier_data_o   = 1'b0;
  assign barrier_src_r_o  = '0;
  assign barrier_dest_r_o = '0;

  localparam PMEM_WORDS  = 512;
  localparam TILE_ADDR_W = 19;   // core_tile DATA_MEM_ADDR_BITS
  localparam TC_W        = 4;    // core_tile thread_count width (8 threads)

  // ------------------------------------------------------------------ endpoint
  `declare_bsg_manycore_packet_s(addr_width_p,data_width_p,x_cord_width_p,y_cord_width_p);

  logic                              in_v_lo, in_we_lo, in_yumi_li;
  logic [data_width_p-1:0]           in_data_lo;
  logic [(data_width_p>>3)-1:0]      in_mask_lo;
  logic [addr_width_p-1:0]           in_addr_lo;
  logic [x_cord_width_p-1:0]         in_src_x_lo;
  logic [y_cord_width_p-1:0]         in_src_y_lo;
  logic                              returning_v_r;
  logic [data_width_p-1:0]           returning_data_r;

  bsg_manycore_packet_s              out_packet_li;
  logic                              out_v_li, out_ready_lo;
  logic [credit_counter_width_lp-1:0] out_credits_used_lo;

  logic                              returned_v_lo;
  logic [data_width_p-1:0]           returned_data_lo;
  logic [bsg_manycore_reg_id_width_gp-1:0] returned_reg_id_lo;

  bsg_manycore_endpoint_standard #(
    .x_cord_width_p(x_cord_width_p)
    ,.y_cord_width_p(y_cord_width_p)
    ,.fifo_els_p(proc_fifo_els_p)
    ,.data_width_p(data_width_p)
    ,.addr_width_p(addr_width_p)
    ,.icache_block_size_in_words_p(icache_block_size_in_words_p)
    ,.credit_counter_width_p(credit_counter_width_lp)
    ,.rev_fifo_els_p(rev_fifo_els_p)
    ,.use_credits_for_local_fifo_p(0)
  ) endp (
    .clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.link_sif_i(link_sif_i)
    ,.link_sif_o(link_sif_o)

    ,.in_v_o(in_v_lo)
    ,.in_data_o(in_data_lo)
    ,.in_mask_o(in_mask_lo)
    ,.in_addr_o(in_addr_lo)
    ,.in_we_o(in_we_lo)
    ,.in_load_info_o()
    ,.in_src_x_cord_o(in_src_x_lo)
    ,.in_src_y_cord_o(in_src_y_lo)
    ,.in_yumi_i(in_yumi_li)

    ,.returning_data_i(returning_data_r)
    ,.returning_v_i(returning_v_r)

    ,.out_v_i(out_v_li)
    ,.out_packet_i(out_packet_li)
    ,.out_credit_or_ready_o(out_ready_lo)

    ,.returned_data_r_o(returned_data_lo)
    ,.returned_reg_id_r_o(returned_reg_id_lo)
    ,.returned_v_r_o(returned_v_lo)
    ,.returned_pkt_type_r_o()
    ,.returned_yumi_i(returned_v_lo)
    ,.returned_fifo_full_o()
    ,.returned_credit_v_r_o()
    ,.returned_credit_reg_id_r_o()

    ,.out_credits_used_o(out_credits_used_lo)

    ,.global_x_i({pod_x_i, my_x_i})
    ,.global_y_i({pod_y_i, my_y_i})
  );

  // ------------------------------------------------------------------ registers
  logic [31:0] base_r, done_addr_r, cycle_r, busy_cyc_r, reads_r, loads_r, writes_r, blocks_r;
  logic [7:0]  block_id_r;
  logic [TC_W-1:0] thread_count_r;
  logic [x_cord_width_p-1:0] caller_x_r;
  logic [y_cord_width_p-1:0] caller_y_r;

  // ------------------------------------------------------------------ incoming requests
  // Every request is taken at once and answered the next cycle.
  wire        is_csr   = in_addr_lo[13] & (in_addr_lo[addr_width_p-1:14] == '0);
  wire        is_pmem  = (in_addr_lo[addr_width_p-1:9] == '0);
  wire [3:0]  csr_sel  = in_addr_lo[3:0];
  wire        start_wr = in_v_lo & in_we_lo & is_csr & (csr_sel == 4'd2);
  wire        pmem_wr  = in_v_lo & in_we_lo & is_pmem;
  assign in_yumi_li = in_v_lo;

  typedef enum logic [2:0] {L_IDLE, L_RESET, L_RUN, L_DRAIN, L_WAKE} launch_e;
  launch_e lstate_r;
  wire busy = (lstate_r != L_IDLE);

  logic [31:0] csr_rdata;
  always_comb begin
    csr_rdata = '0;
    if (is_csr) begin
      case (csr_sel)
        4'd0: csr_rdata = base_r;
        4'd1: csr_rdata = done_addr_r;
        4'd3: csr_rdata = {31'b0, busy};
        4'd4: csr_rdata = cycle_r;
        4'd5: csr_rdata = busy_cyc_r;
        4'd6: csr_rdata = reads_r;
        4'd7: csr_rdata = writes_r;
        4'd8: csr_rdata = NUMBER_FORMAT;
        4'd9: csr_rdata = blocks_r;
        4'd10: csr_rdata = loads_r;
        4'd11: csr_rdata = RB_LINES;
        default: csr_rdata = '0;
      endcase
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      returning_v_r <= 1'b0;
      returning_data_r <= '0;
      base_r <= '0;
      done_addr_r <= '0;
    end else begin
      returning_v_r <= in_v_lo;
      returning_data_r <= in_we_lo ? '0 : csr_rdata;
      if (in_v_lo & in_we_lo & is_csr) begin
        if (csr_sel == 4'd0) base_r <= in_data_lo;
        if (csr_sel == 4'd1) done_addr_r <= in_data_lo;
      end
    end
  end

  // ------------------------------------------------------------------ program memory + icache
  logic [15:0] pmem [0:PMEM_WORDS-1];
  always_ff @(posedge clk_i)
    if (pmem_wr) pmem[in_addr_lo[8:0]] <= in_data_lo[15:0];

  // A program write invalidates the instruction cache (as the chip's reset
  // at each launch does), so a reloaded program is never served stale.
  logic icache_flush_r;
  always_ff @(posedge clk_i)
    icache_flush_r <= reset_i | pmem_wr;

  logic                   prog_v_lo, prog_ready_li;
  logic [8:0]             prog_addr_lo;
  logic [15:0]            prog_data_li;
  logic                   pm_v_lo;
  logic [8:0]             pm_addr_lo;
  logic                   pm_ready_r;
  logic [15:0]            pm_data_r;

  sf1_shared_icache #(
    .NUM_PORTS(1), .ADDR_BITS(9), .DATA_BITS(16), .ENTRIES(32)
  ) icache (
    .clk(clk_i)
    ,.reset(icache_flush_r)
    ,.consumer_read_valid(prog_v_lo)
    ,.consumer_read_address_flat(prog_addr_lo)
    ,.consumer_read_ready(prog_ready_li)
    ,.consumer_read_data_flat(prog_data_li)
    ,.mem_read_valid(pm_v_lo)
    ,.mem_read_address(pm_addr_lo)
    ,.mem_read_ready(pm_ready_r)
    ,.mem_read_data(pm_data_r)
  );

  // Program memory answers a miss in one cycle: a one-cycle ready pulse with
  // the data, then a cycle for the cache to drop valid.
  logic pm_hold_r;
  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      pm_ready_r <= 1'b0;
      pm_hold_r <= 1'b0;
    end else begin
      pm_ready_r <= pm_v_lo & ~pm_ready_r & ~pm_hold_r;
      pm_hold_r  <= pm_ready_r;
      pm_data_r  <= pmem[pm_addr_lo];
    end
  end

  // ------------------------------------------------------------------ core tile
  logic core_reset, core_start, core_done;
  logic                    d_rv_lo, d_wv_lo;
  logic [TILE_ADDR_W-1:0]  d_raddr_lo, d_waddr_lo;
  logic [15:0]             d_wdata_lo;
  logic                    d_rready_r, d_wready_r;
  logic [15:0]             d_rdata_r;

  sf1_core_tile #(
    .DATA_MEM_ADDR_BITS(TILE_ADDR_W)
    ,.DATA_MEM_DATA_BITS(16)
    ,.PROGRAM_MEM_ADDR_BITS(9)
    ,.PROGRAM_MEM_DATA_BITS(16)
    ,.THREADS_PER_BLOCK(8)
    ,.SYSTOLIC_SIZE(8)
    ,.NUMBER_FORMAT(NUMBER_FORMAT)
  ) tile (
    .clk(clk_i)
    ,.reset(reset_i)
    ,.core_reset(core_reset)
    ,.start(core_start)
    ,.done(core_done)
    ,.block_id(block_id_r)
    ,.thread_count(thread_count_r)
    ,.program_mem_read_valid(prog_v_lo)
    ,.program_mem_read_address(prog_addr_lo)
    ,.program_mem_read_ready(prog_ready_li)
    ,.program_mem_read_data(prog_data_li)
    ,.data_mem_read_valid(d_rv_lo)
    ,.data_mem_read_address(d_raddr_lo)
    ,.data_mem_read_ready(d_rready_r)
    ,.data_mem_read_data(d_rdata_r)
    ,.data_mem_write_valid(d_wv_lo)
    ,.data_mem_write_address(d_waddr_lo)
    ,.data_mem_write_data(d_wdata_lo)
    ,.data_mem_write_ready(d_wready_r)
  );

  // ------------------------------------------------------------------ data channel -> mesh
  // EVA of the tile's word: BASE + 2 * address (byte address of a halfword).
  //
  // RB_LINES = 0 (direct): each read is one halfword remote load, answered
  //   when it returns; one read in flight, as core_tile allows.
  // RB_LINES > 0 (read buffer): RB_LINES lines of one vcache block (8 words)
  //   in the adapter, LRU. A read that misses fetches its whole line with 8
  //   word loads in flight and is answered when its word arrives; a read
  //   that hits is answered the next cycle and starts a prefetch of the next
  //   line if it is not held. Writes go to memory as in direct mode and
  //   update a held copy. Every line is dropped at START.
  typedef enum logic [2:0] {D_IDLE, D_RWAIT, D_RDONE, D_WDONE} data_e;
  data_e dstate_r;

  wire [31:0] d_eva = base_r + {12'b0, (d_rv_lo ? d_raddr_lo : d_waddr_lo), 1'b0};

  logic [x_cord_width_p-1:0] npa_x;
  logic [y_cord_width_p-1:0] npa_y;
  logic [addr_width_p-1:0]   npa_epa;
  logic                      npa_invalid;
  logic [31:0]               req_eva;     // the EVA of the request on the port

  bsg_manycore_eva_to_npa #(
    .data_width_p(data_width_p)
    ,.addr_width_p(addr_width_p)
    ,.x_cord_width_p(x_cord_width_p)
    ,.y_cord_width_p(y_cord_width_p)
    ,.pod_x_cord_width_p(pod_x_cord_width_p)
    ,.pod_y_cord_width_p(pod_y_cord_width_p)
    ,.num_tiles_x_p(num_tiles_x_p)
    ,.num_tiles_y_p(num_tiles_y_p)
    ,.vcache_block_size_in_words_p(vcache_block_size_in_words_p)
    ,.vcache_size_p(vcache_size_p)
    ,.vcache_sets_p(vcache_sets_p)
    ,.ipoly_hashing_p(ipoly_hashing_p)
  ) eva2npa (
    .eva_i(req_eva)
    ,.tgo_x_i('0)
    ,.tgo_y_i('0)
    ,.pod_x_i(pod_x_i)
    ,.pod_y_i(pod_y_i)
    ,.x_cord_o(npa_x)
    ,.y_cord_o(npa_y)
    ,.epa_o(npa_epa)
    ,.is_invalid_addr_o(npa_invalid)
  );

  wire credit_ok = (out_credits_used_lo < credit_counter_width_lp'(max_out_credits_p));

  // The data path's outgoing request; the wake-up store has the port when the
  // launch FSM asks for it (the core is in reset then, so the data path is idle).
  logic wake_v;
  logic dreq_v, dreq_is_load;
  logic [3:0] dreq_mask;
  logic [31:0] dreq_payload;
  logic [bsg_manycore_reg_id_width_gp-1:0] dreq_reg_id;
  bsg_manycore_load_info_s dreq_info;

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
    end else if (dreq_is_load) begin
      out_packet_li.op_v2 = e_remote_load;
      out_packet_li.reg_id = dreq_reg_id;
      out_packet_li.payload.load_info_s.load_info = dreq_info;
      out_packet_li.addr = npa_epa;
      out_packet_li.x_cord = npa_x;
      out_packet_li.y_cord = npa_y;
    end else begin
      out_packet_li.op_v2 = e_remote_store;
      out_packet_li.reg_id.store_mask_s.mask = dreq_mask;
      out_packet_li.payload = dreq_payload;
      out_packet_li.addr = npa_epa;
      out_packet_li.x_cord = npa_x;
      out_packet_li.y_cord = npa_y;
    end
  end
  assign out_v_li = wake_v | dreq_v;
  wire dreq_fire = dreq_v & out_ready_lo & ~wake_v;

  // Stores are the same in both modes.
  assign dreq_mask    = d_eva[1] ? 4'b1100 : 4'b0011;
  assign dreq_payload = {d_wdata_lo, d_wdata_lo};

  logic rd_answer;         // a tile read answered this cycle (for the counters)
  logic net_load;          // a load packet sent this cycle
  assign net_load = dreq_fire & dreq_is_load;

  if (RB_LINES == 0) begin : direct
    assign req_eva      = d_eva;
    assign dreq_is_load = d_rv_lo;
    assign dreq_reg_id  = '0;
    assign dreq_info    = '{float_wb: 1'b0, icache_fetch: 1'b0, is_unsigned_op: 1'b1,
                            is_byte_op: 1'b0, is_hex_op: 1'b1, part_sel: d_eva[1:0]};
    assign dreq_v       = (dstate_r == D_IDLE) & (d_rv_lo | d_wv_lo) & credit_ok;
    assign rd_answer    = (dstate_r == D_RWAIT) & returned_v_lo;

    always_ff @(posedge clk_i) begin
      if (reset_i) begin
        dstate_r <= D_IDLE;
        d_rready_r <= 1'b0;
        d_wready_r <= 1'b0;
        d_rdata_r <= '0;
      end else begin
        d_rready_r <= 1'b0;
        d_wready_r <= 1'b0;
        case (dstate_r)
          D_IDLE: if (dreq_fire) begin
            if (d_rv_lo) dstate_r <= D_RWAIT;
            else begin
              d_wready_r <= 1'b1;
              dstate_r <= D_WDONE;
            end
          end
          D_RWAIT: if (returned_v_lo) begin
            d_rdata_r <= returned_data_lo[15:0];
            d_rready_r <= 1'b1;
            dstate_r <= D_RDONE;
          end
          // The ready pulse is seen this cycle; the tile drops valid with it.
          D_RDONE: dstate_r <= D_IDLE;
          D_WDONE: dstate_r <= D_IDLE;
          default: dstate_r <= D_IDLE;
        endcase
      end
    end
  end else begin : rbuf
    localparam LW   = vcache_block_size_in_words_p;
    localparam LB   = `BSG_SAFE_CLOG2(LW);
    localparam NLB  = `BSG_SAFE_CLOG2(RB_LINES);
    localparam TAGW = 30 - LB;

    logic [TAGW-1:0]     tag_r   [RB_LINES];
    logic [RB_LINES-1:0] lval_r;
    logic [LW-1:0]       wval_r  [RB_LINES];
    logic [31:0]         data_r  [RB_LINES][LW];
    logic [NLB-1:0]      age_r   [RB_LINES];        // 0 = most recently used

    wire [TAGW-1:0] rq_tag  = d_eva[31:LB+2];
    wire [LB-1:0]   rq_word = d_eva[LB+1:2];

    logic hit, nxt_held, hit_l_oldest;
    logic [NLB-1:0] hit_l, victim;
    always_comb begin
      hit = 1'b0; hit_l = '0; nxt_held = 1'b0; victim = '0; hit_l_oldest = 1'b0;
      for (int l = 0; l < RB_LINES; l++)
        if (lval_r[l] && tag_r[l] == rq_tag) begin
          hit = 1'b1; hit_l = NLB'(l); hit_l_oldest = (age_r[l] == NLB'(RB_LINES - 1));
        end
      // The victim is the oldest line once a hit has touched its own line:
      // the next oldest if the hit line was the oldest.
      for (int l = 0; l < RB_LINES; l++) begin
        if (lval_r[l] && tag_r[l] == rq_tag + 1'b1) nxt_held = 1'b1;
        if (age_r[l] == ((hit && hit_l_oldest) ? NLB'(RB_LINES - 2) : NLB'(RB_LINES - 1))) victim = NLB'(l);
      end
    end
    wire word_ok = hit & wval_r[hit_l][rq_word];

    // Line fetch engine: one line at a time, LW word loads, reg_id = word.
    logic           f_busy_r;
    logic [NLB-1:0] f_line_r;
    logic [TAGW-1:0] f_tag_r;
    logic [LB:0]    f_sent_r, f_recv_r;
    wire fetch_send = f_busy_r & (f_sent_r < (LB+1)'(LW)) & credit_ok;

    // Fetch packets have the port before stores; a store waits for a fetch
    // of its own line, so a returning word never overwrites newer data.
    wire wr_ok = (dstate_r == D_IDLE) & d_wv_lo & ~d_rv_lo & ~(f_busy_r & (f_tag_r == rq_tag)) & credit_ok;
    assign dreq_is_load = fetch_send;
    assign dreq_v       = fetch_send | wr_ok;
    assign req_eva      = fetch_send ? {f_tag_r, f_sent_r[LB-1:0], 2'b00} : d_eva;
    assign dreq_reg_id  = bsg_manycore_reg_id_width_gp'(f_sent_r[LB-1:0]);
    assign dreq_info    = '0;                       // LW

    wire rd_hit   = (dstate_r == D_IDLE) & d_rv_lo & word_ok;
    wire rd_miss  = (dstate_r == D_IDLE) & d_rv_lo & ~hit & ~f_busy_r;
    wire pf_start = rd_hit & ~nxt_held & ~f_busy_r;
    wire alloc    = rd_miss | pf_start;
    wire [TAGW-1:0] alloc_tag = rd_miss ? rq_tag : rq_tag + 1'b1;
    assign rd_answer = rd_hit;

    // LRU ages: a line is touched (made most recent) when it is hit, then
    // when it is allocated; a hit that starts a prefetch touches both, in
    // that order.
    logic [NLB-1:0] age_n [RB_LINES];
    always_comb begin
      logic [NLB-1:0] a1 [RB_LINES];
      for (int l = 0; l < RB_LINES; l++) a1[l] = age_r[l];
      if (rd_hit)
        for (int l = 0; l < RB_LINES; l++)
          a1[l] = (NLB'(l) == hit_l) ? '0 : (age_r[l] < age_r[hit_l]) ? age_r[l] + 1'b1 : age_r[l];
      for (int l = 0; l < RB_LINES; l++) age_n[l] = a1[l];
      if (alloc)
        for (int l = 0; l < RB_LINES; l++)
          age_n[l] = (NLB'(l) == victim) ? '0 : (a1[l] < a1[victim]) ? a1[l] + 1'b1 : a1[l];
    end
    wire wr_hit = dreq_fire & ~dreq_is_load & hit;

    always_ff @(posedge clk_i) begin
      if (reset_i) begin
        dstate_r <= D_IDLE;
        d_rready_r <= 1'b0;
        d_wready_r <= 1'b0;
        d_rdata_r <= '0;
        lval_r <= '0;
        f_busy_r <= 1'b0;
        f_sent_r <= '0;
        f_recv_r <= '0;
        for (int l = 0; l < RB_LINES; l++) age_r[l] <= NLB'(l);
      end else begin
        d_rready_r <= 1'b0;
        d_wready_r <= 1'b0;

        if (start_wr & ~busy) lval_r <= '0;

        for (int l = 0; l < RB_LINES; l++) age_r[l] <= age_n[l];

        if (alloc) begin
          tag_r[victim] <= alloc_tag;
          lval_r[victim] <= 1'b1;
          wval_r[victim] <= '0;
          f_busy_r <= 1'b1;
          f_line_r <= victim;
          f_tag_r <= alloc_tag;
          f_sent_r <= '0;
          f_recv_r <= '0;
        end else begin
          if (dreq_fire & dreq_is_load) f_sent_r <= f_sent_r + 1'b1;
          if (returned_v_lo) begin
            data_r[f_line_r][returned_reg_id_lo[LB-1:0]] <= returned_data_lo;
            wval_r[f_line_r][returned_reg_id_lo[LB-1:0]] <= 1'b1;
            f_recv_r <= f_recv_r + 1'b1;
            if (f_recv_r == (LB+1)'(LW - 1)) f_busy_r <= 1'b0;
          end
        end

        if (wr_hit) begin
          if (d_eva[1]) data_r[hit_l][rq_word][31:16] <= d_wdata_lo;
          else          data_r[hit_l][rq_word][15:0]  <= d_wdata_lo;
        end

        case (dstate_r)
          D_IDLE: begin
            if (rd_hit) begin
              d_rdata_r <= d_eva[1] ? data_r[hit_l][rq_word][31:16] : data_r[hit_l][rq_word][15:0];
              d_rready_r <= 1'b1;
              dstate_r <= D_RDONE;
            end else if (dreq_fire & ~dreq_is_load) begin
              d_wready_r <= 1'b1;
              dstate_r <= D_WDONE;
            end
          end
          D_RDONE: dstate_r <= D_IDLE;
          D_WDONE: dstate_r <= D_IDLE;
          default: dstate_r <= D_IDLE;
        endcase
      end
    end

    // synopsys translate_off
    always_ff @(negedge clk_i) begin
      if (~reset_i & returned_v_lo & ~f_busy_r)
        $error("[sf_hb_accel] load returned with no line fetch in flight");
      if (~reset_i & alloc & f_busy_r)
        $error("[sf_hb_accel] line fetch started while one is in flight");
    end
    // synopsys translate_on
  end

  // ------------------------------------------------------------------ launch FSM
  assign core_reset = (lstate_r != L_RUN);
  assign core_start = (lstate_r == L_RUN);
  assign wake_v     = (lstate_r == L_WAKE);

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      lstate_r <= L_IDLE;
      block_id_r <= '0;
      thread_count_r <= '0;
      caller_x_r <= '0;
      caller_y_r <= '0;
      cycle_r <= '0;
      busy_cyc_r <= '0;
      reads_r <= '0;
      loads_r <= '0;
      writes_r <= '0;
      blocks_r <= '0;
    end else begin
      cycle_r <= cycle_r + 1;
      if (core_start) busy_cyc_r <= busy_cyc_r + 1;
      if (rd_answer) reads_r <= reads_r + 1;
      if (net_load) loads_r <= loads_r + 1;
      if (dreq_fire & ~dreq_is_load) writes_r <= writes_r + 1;
      case (lstate_r)
        L_IDLE: if (start_wr) begin
          block_id_r <= in_data_lo[7:0];
          thread_count_r <= in_data_lo[8+:TC_W];
          caller_x_r <= in_src_x_lo;
          caller_y_r <= in_src_y_lo;
          lstate_r <= L_RESET;
        end
        L_RESET: lstate_r <= L_RUN;
        L_RUN: if (core_done) lstate_r <= L_DRAIN;
        // Every store acknowledged before the launching core is told.
        L_DRAIN: if ((dstate_r == D_IDLE) & ~d_rv_lo & ~d_wv_lo & (out_credits_used_lo == '0))
          lstate_r <= L_WAKE;
        L_WAKE: if (out_ready_lo) begin
          blocks_r <= blocks_r + 1;
          lstate_r <= L_IDLE;
        end
        default: lstate_r <= L_IDLE;
      endcase
    end
  end

  // synopsys translate_off
  initial $display("## sf_hb_accel: SuperFloat v1 tile, NUMBER_FORMAT %0d, RB_LINES %0d, at %m", NUMBER_FORMAT, RB_LINES);

  always_ff @(negedge clk_i) begin
    if (~reset_i & dreq_v & npa_invalid)
      $error("[sf_hb_accel] invalid data EVA %h (x,y=%0d,%0d)", req_eva, my_x_i, my_y_i);
    if (~reset_i & start_wr & busy)
      $error("[sf_hb_accel] START while busy (x,y=%0d,%0d)", my_x_i, my_y_i);
  end
  // synopsys translate_on

endmodule

// One module per number format, so the hetero socket can place each.
`define SF_HB_ACCEL_FORMAT(NAME, FMT, RB)                                       \
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
  sf_hb_accel #(.x_cord_width_p(x_cord_width_p), .y_cord_width_p(y_cord_width_p) \
    , .pod_x_cord_width_p(pod_x_cord_width_p), .pod_y_cord_width_p(pod_y_cord_width_p) \
    , .data_width_p(data_width_p), .addr_width_p(addr_width_p)                \
    , .dmem_size_p(dmem_size_p), .vcache_size_p(vcache_size_p)                \
    , .vcache_block_size_in_words_p(vcache_block_size_in_words_p)             \
    , .vcache_sets_p(vcache_sets_p), .icache_entries_p(icache_entries_p)      \
    , .icache_tag_width_p(icache_tag_width_p)                                 \
    , .icache_block_size_in_words_p(icache_block_size_in_words_p)             \
    , .num_tiles_x_p(num_tiles_x_p), .num_tiles_y_p(num_tiles_y_p)            \
    , .fwd_fifo_els_p(fwd_fifo_els_p), .rev_fifo_els_p(rev_fifo_els_p)        \
    , .barrier_dirs_p(barrier_dirs_p), .ipoly_hashing_p(ipoly_hashing_p)      \
    , .debug_p(debug_p), .NUMBER_FORMAT(FMT), .RB_LINES(RB)) a (.*);                      \
endmodule

`SF_HB_ACCEL_FORMAT(sf_hb_accel_sf16, 0, 0)
`SF_HB_ACCEL_FORMAT(sf_hb_accel_fp16, 1, 0)
`SF_HB_ACCEL_FORMAT(sf_hb_accel_bf16, 2, 0)
`SF_HB_ACCEL_FORMAT(sf_hb_accel_sf16_rb, 0, 8)
`SF_HB_ACCEL_FORMAT(sf_hb_accel_fp16_rb, 1, 8)
`SF_HB_ACCEL_FORMAT(sf_hb_accel_bf16_rb, 2, 8)
