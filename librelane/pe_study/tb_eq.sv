`timescale 1ns/1ps
module tb_eq;
  reg clk = 0, reset = 1, clear = 0, load = 0, comp = 0;
  reg [15:0] a = 0, b = 0;
  always #5 clk = ~clk;
  wire [15:0] o_a, o_b, o_acc, l_a, l_b, p_a, p_b;
  wire signed [15:0] l_acc, p_acc;
  systolic_pe_base old (.clk(clk), .reset(reset), .enable(1'b1), .clear_acc(clear), .load_weight(load),
                   .compute_enable(comp), .a_in(a), .b_in(b), .a_out(o_a), .b_out(o_b), .acc_out(o_acc));
  systolic_pe lean (.clk(clk), .reset(reset), .clear_acc(clear), .load_weight(load), .compute_enable(comp),
                  .a_in(a), .b_in(b), .a_out(l_a), .b_out(l_b), .acc_raw(l_acc));
  systolic_pe_pipe pipe (.clk(clk), .reset(reset), .clear_acc(clear), .load_weight(load), .compute_enable(comp),
                  .a_in(a), .b_in(b), .a_out(p_a), .b_out(p_b), .acc_raw(p_acc));
  function [15:0] conv(input signed [15:0] x);
    conv = x[15] ? {1'b1, 15'(-x)} : x;
  endfunction
  function [15:0] canon(input [15:0] x); canon = (x == 16'h8000) ? 16'h0000 : x; endfunction
  reg [15:0] old_prev = 16'h0000;  // reference output one cycle earlier
  reg clear_prev = 0;
  integer since_comp = 100;
  integer i, err_l = 0, err_p = 0, clears = 0, loads = 0, comps = 0, sats = 0;
  initial begin
    repeat (3) @(posedge clk);
    reset = 0;
    for (i = 0; i < 200000; i = i + 1) begin
      @(negedge clk);
      // Compare the previous edge's results.
      if (o_acc !== conv(l_acc)) begin err_l = err_l + 1; if (err_l < 5) $display("lean mismatch @%0d old=%h lean=%h", i, o_acc, conv(l_acc)); end
      if (!clear && old_prev !== conv(p_acc)) begin err_p = err_p + 1; if (err_p < 5) $display("pipe mismatch @%0d old(prev)=%h pipe=%h", i, old_prev, conv(p_acc)); end
      if (o_acc == 16'h7FFF || o_acc == 16'hFFFF) sats = sats + 1;
      old_prev = o_acc;
      // Random stimulus; large magnitudes sometimes, to reach saturation.
      a = canon($random); if ($urandom % 4) a = canon({a[15], 2'b0, a[12:0]});
      b = canon($random);
      clear_prev = clear;
      clear = (($urandom % 97) == 0) && (since_comp > 4);
      load  = ($urandom % 13) == 0;
      comp  = !clear && (($urandom % 3) == 0);
      since_comp = comp ? 0 : since_comp + 1;
      clears = clears + clear; loads = loads + load; comps = comps + comp;
    end
    $display("cycles=200000 clears=%0d loads=%0d computes=%0d saturated_samples=%0d", clears, loads, comps, sats);
    $display("lean mismatches=%0d pipe mismatches=%0d", err_l, err_p);
    $finish;
  end
endmodule
