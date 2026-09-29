`timescale 1ns/1ps
// Gate-level power stimulus shared by the SF16, FP16 and BF16 PEs: one weight
// load (~0.337), then a compute every second cycle with a fresh random
// activation and a clear every 64 computes. Every second cycle is the FP PE's
// highest compute rate, so all three PEs see the same MAC rate.
//   SF16: |a| < 0.25 (as in the first PE study)
//   FP16/BF16: |a| in [0.125, 2), random mantissa
module tb_power_fp;
  parameter FMT = 0;                 // 0 SF16, 1 FP16, 2 BF16
  reg clk = 0, reset = 1, clear = 0, load = 0, comp = 0;
  reg [15:0] a = 0, b = 0;
  always #10 clk = ~clk;             // 20 ns
  wire [15:0] a_out, b_out, acc;
`ifdef SF16
  systolic_pe dut (.clk(clk), .reset(reset), .clear_acc(clear), .load_weight(load), .compute_enable(comp),
                   .a_in(a), .b_in(b), .a_out(a_out), .b_out(b_out), .acc_raw(acc));
`else
  fp_systolic_pe dut (.clk(clk), .reset(reset), .clear_acc(clear), .load_weight(load), .compute_enable(comp),
                      .a_in(a), .b_in(b), .a_out(a_out), .b_out(b_out), .acc(acc));
`endif
  integer i, r, seed = 12345;
  function [15:0] act(input integer rnd);
    reg [15:0] x;
    begin
      if (FMT == 0) begin
        x = rnd[15:0] & 16'h9FFF;
        act = (x == 16'h8000) ? 16'h0000 : x;
      end else if (FMT == 1)        // FP16: exponent 12..15 (bias 15)
        act = {rnd[15], 5'd12 + {3'b0, rnd[14:13]}, rnd[9:0]};
      else                          // BF16: exponent 124..127 (bias 127)
        act = {rnd[15], 8'd124 + {6'b0, rnd[14:13]}, rnd[6:0]};
    end
  endfunction
  initial begin
    repeat (4) @(posedge clk);
    @(negedge clk) reset = 0;
    @(negedge clk) begin b = (FMT == 0) ? 16'h2B1C : (FMT == 1) ? 16'h3564 : 16'h3EAD; load = 1; end
    @(negedge clk) load = 0;
    $dumpfile("power.vcd");
    $dumpvars(0, tb_power_fp.dut);
    for (i = 0; i < 5000; i = i + 1) begin
      @(negedge clk);
      r = $random(seed);
      a = act(r);
      comp = 1;
      clear = (i % 64) == 63;
      @(negedge clk);
      comp = 0;
      clear = 0;
    end
    repeat (4) @(posedge clk);
    $finish;
  end
endmodule
