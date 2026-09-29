`timescale 1ns/1ps
// Full-throughput MAC stream for gate-level power: one weight load, then a
// compute every cycle with fresh random activations, a clear every 64 cycles.
// Same stimulus for every PE variant (BASE selects the original port list).
module tb_power;
  reg clk = 0, reset = 1, clear = 0, load = 0, comp = 0;
  reg [15:0] a = 0, b = 0;
  always #10 clk = ~clk;   // 20 ns
`ifdef BASE
  wire [15:0] a_out, b_out, acc;
  systolic_pe dut (.clk(clk), .reset(reset), .enable(1'b1), .clear_acc(clear), .load_weight(load),
                   .compute_enable(comp), .a_in(a), .b_in(b), .a_out(a_out), .b_out(b_out), .acc_out(acc));
`else
  wire [15:0] a_out, b_out, acc;
  systolic_pe dut (.clk(clk), .reset(reset), .clear_acc(clear), .load_weight(load), .compute_enable(comp),
                   .a_in(a), .b_in(b), .a_out(a_out), .b_out(b_out), .acc_raw(acc));
`endif
  function [15:0] canon(input [15:0] x); canon = (x == 16'h8000) ? 16'h0000 : x; endfunction
  integer i, seed = 12345;
  initial begin
    repeat (4) @(posedge clk);
    @(negedge clk) reset = 0;
    @(negedge clk) begin b = 16'h2B1C; load = 1; end
    @(negedge clk) load = 0;
    $dumpfile("power.vcd");
    $dumpvars(0, tb_power.dut);
    for (i = 0; i < 5000; i = i + 1) begin
      @(negedge clk);
      a = canon({$random(seed)} & 16'h9FFF);   // |a| < 0.25 keeps most sums unsaturated
      comp = 1;
      clear = (i % 64) == 63;
    end
    @(negedge clk) comp = 0;
    repeat (4) @(posedge clk);
    $finish;
  end
endmodule
