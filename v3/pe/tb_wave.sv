`default_nettype none
`timescale 1ns/1ps
// tb_block.sv with the wavefront swap token (WAVE = 1): each line of STIM
// gives w_shift, w_swap, a_west, w_north, psum_north, tok_west. OUT is in
// binary, so a lane is unknown only if its own bits are.
module tb_wave;
    reg clk = 0;
    reg w_shift, w_swap;
    reg  [`N*`IW-1:0] a_west, w_north;
    reg  [`N*`CW-1:0] psum_north;
    reg  [`N-1:0]     tok_west;
    wire [`N*`IW-1:0] a_east;
    wire [`N*`CW-1:0] psum_south;
    `TOP dut (.clk(clk), .w_shift(w_shift), .w_swap(w_swap), .a_west(a_west), .tok_west(tok_west),
              .w_north(w_north), .psum_north(psum_north), .a_east(a_east), .psum_south(psum_south));
    integer fi, fo, n;
    initial begin
        fi = $fopen("stim.txt", "r");
        fo = $fopen("out.txt", "w");
        while (!$feof(fi)) begin
            n = $fscanf(fi, "%h %h %h %h %h %h\n", w_shift, w_swap, a_west, w_north, psum_north, tok_west);
            if (n == 6) begin
                #1 clk = 1;
                #1 $fwrite(fo, "%b\n", psum_south);
                #1 clk = 0;
            end
        end
        $fclose(fo);
        $finish;
    end
endmodule
