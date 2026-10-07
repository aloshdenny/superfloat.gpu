`default_nettype none
`timescale 1ps/1ps
// Gate-level power and equivalence run of one S2 block (gl_sim.sh): applies
// STIM one line per clock of `PERIOD ps, writes psum_south after every edge
// to out.txt, and dumps a VCD from cycle `DUMP_FROM until it stops at `DUMP_TO.
// With WAVE the stimulus has a sixth field, the rows' swap tokens (v3_block WAVE = 1).
module tb_block;
    reg clk = 0;
    reg w_shift, w_swap;
    reg  [`N*`IW-1:0] a_west, w_north;
    reg  [`N*`CW-1:0] psum_north;
    reg  [`N-1:0]     tok_west = 0;
    wire [`N*`IW-1:0] a_east;
    wire [`N*`CW-1:0] psum_south;
`ifdef WAVE
    `TOP dut (.clk(clk), .w_shift(w_shift), .w_swap(w_swap), .a_west(a_west), .tok_west(tok_west),
              .w_north(w_north), .psum_north(psum_north), .a_east(a_east),
              .psum_south(psum_south));
`else
    `TOP dut (.clk(clk), .w_shift(w_shift), .w_swap(w_swap), .a_west(a_west),
              .w_north(w_north), .psum_north(psum_north), .a_east(a_east),
              .psum_south(psum_south));
`endif
    integer fi, fo, n, cyc;
    initial begin
        fi = $fopen("stim.txt", "r");
        fo = $fopen("out.txt", "w");
        cyc = 0;
        while (!$feof(fi) && cyc < `DUMP_TO) begin
`ifdef WAVE
            n = $fscanf(fi, "%h %h %h %h %h %h\n", w_shift, w_swap, a_west, w_north, psum_north, tok_west) - 1;
`else
            n = $fscanf(fi, "%h %h %h %h %h\n", w_shift, w_swap, a_west, w_north, psum_north);
`endif
            if (n == 5) begin
                if (cyc == `DUMP_FROM) begin
                    $dumpfile("act.vcd");
                    $dumpvars(2, dut);    // cell pins: OpenSTA maps pin names, not flat nets
                end
                #(`PERIOD/2) clk = 1;
                #(`PERIOD/4) $fwrite(fo, "%h\n", psum_south);
                #(`PERIOD/4) clk = 0;
                cyc = cyc + 1;
            end
        end
        $fclose(fo);
        $finish;
    end
endmodule
