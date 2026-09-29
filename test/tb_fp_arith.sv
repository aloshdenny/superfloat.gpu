`default_nettype none
`timescale 1ns/1ns

// Vector testbench for src/fp_arith.sv: fp_mul -> fp_add -> fp_round must equal
// the reference round(a*b + c) of helpers/fp16fmt.py for every line of VEC
// ("a b c expected", hex). Vectors: test/fp_arith_vectors.py. Run: make test_fp_arith
module tb_fp_arith;
    parameter EXP_BITS  = 5;
    parameter MANT_BITS = 10;
    parameter VEC = "build/fp_arith_fp16.hex";
    localparam W = 1 + EXP_BITS + MANT_BITS, M = MANT_BITS + 1, EW = EXP_BITS + 4, AW = 2 * M + 3;

    reg  [W-1:0] a, b, c, want;
    wire [2*M-1:0] prod;
    wire signed [EW-1:0] p_top, s_top;
    wire p_sign, p_zero, p_inf, p_nan;
    wire [AW:0] mag;
    wire s_sign, s_zero, s_inf, s_nan;
    wire [W-1:0] got;

    fp_mul #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_mul (
        .a(a), .b(b), .prod(prod), .top_exp(p_top),
        .sign(p_sign), .zero(p_zero), .inf(p_inf), .nan(p_nan));
    fp_add #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_add (
        .prod(prod), .p_top(p_top), .p_sign(p_sign), .p_zero(p_zero), .p_inf(p_inf), .p_nan(p_nan),
        .c(c), .mag(mag), .top_exp(s_top), .sign(s_sign), .zero(s_zero), .inf(s_inf), .nan(s_nan));
    fp_round #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_round (
        .mag(mag), .top_exp(s_top), .sign(s_sign), .zero(s_zero), .inf(s_inf), .nan(s_nan),
        .result(got));

    integer fd, n, count, bad;
    initial begin
        fd = $fopen(VEC, "r");
        if (fd == 0) begin
            $display("FAIL cannot open %s", VEC);
            $finish;
        end
        count = 0;
        bad = 0;
        while (!$feof(fd)) begin
            n = $fscanf(fd, "%h %h %h %h\n", a, b, c, want);
            if (n == 4) begin
                #1;
                count = count + 1;
                if (got !== want) begin
                    bad = bad + 1;
                    if (bad <= 10)
                        $display("MISMATCH a=%h b=%h c=%h got=%h want=%h", a, b, c, got, want);
                end
            end
        end
        $display("%s %s: %0d vectors, %0d mismatches", (bad == 0 && count > 0) ? "PASS" : "FAIL", VEC, count, bad);
        $finish;
    end
endmodule
