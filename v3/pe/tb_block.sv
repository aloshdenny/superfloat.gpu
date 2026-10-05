`default_nettype none
`timescale 1ns/1ps
// Cycle-by-cycle driver for one S2 block variant (check_block.py). Each line
// of STIM gives one cycle's inputs; OUT gets the outputs after that edge.
// Compile with -DTOP=blk_<variant> -DIW=<bits> -DCW=<bits> -DN=<n>.
module tb_block;
    reg clk = 0;
    reg w_shift, w_swap;
    reg  [`N*`IW-1:0] a_west, w_north;
    reg  [`N*`CW-1:0] psum_north;
    wire [`N*`IW-1:0] a_east;
    wire [`N*`CW-1:0] psum_south;
    `TOP dut (.clk(clk), .w_shift(w_shift), .w_swap(w_swap), .a_west(a_west),
              .w_north(w_north), .psum_north(psum_north), .a_east(a_east),
              .psum_south(psum_south));
    integer fi, fo, n;
    initial begin
        fi = $fopen("stim.txt", "r");
        fo = $fopen("out.txt", "w");
        while (!$feof(fi)) begin
            n = $fscanf(fi, "%h %h %h %h %h\n", w_shift, w_swap, a_west, w_north, psum_north);
            if (n == 5) begin
                #1 clk = 1;
                #1 $fwrite(fo, "%h\n", psum_south);
                #1 clk = 0;
            end
        end
        $fclose(fo);
        $finish;
    end
endmodule
