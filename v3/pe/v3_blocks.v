`default_nettype none
module fp_mul (
	a,
	b,
	prod,
	top_exp,
	sign,
	zero,
	inf,
	nan
);
	parameter EXP_BITS = 5;
	parameter MANT_BITS = 10;
	parameter W = (1 + EXP_BITS) + MANT_BITS;
	parameter M = MANT_BITS + 1;
	parameter EW = EXP_BITS + 4;
	input wire [W - 1:0] a;
	input wire [W - 1:0] b;
	output wire [(2 * M) - 1:0] prod;
	output wire signed [EW - 1:0] top_exp;
	output wire sign;
	output wire zero;
	output wire inf;
	output wire nan;
	localparam integer BIAS = (1 << (EXP_BITS - 1)) - 1;
	localparam integer EXP_ONE = (1 << EXP_BITS) - 1;
	wire [EXP_BITS - 1:0] ae = a[W - 2-:EXP_BITS];
	wire [EXP_BITS - 1:0] be = b[W - 2-:EXP_BITS];
	wire [MANT_BITS - 1:0] af = a[MANT_BITS - 1:0];
	wire [MANT_BITS - 1:0] bf = b[MANT_BITS - 1:0];
	wire a_zero = ae == 0;
	wire b_zero = be == 0;
	wire a_inf = (ae == EXP_ONE) && (af == 0);
	wire b_inf = (be == EXP_ONE) && (bf == 0);
	wire a_nan = (ae == EXP_ONE) && (af != 0);
	wire b_nan = (be == EXP_ONE) && (bf != 0);
	assign sign = a[W - 1] ^ b[W - 1];
	assign nan = ((a_nan || b_nan) || (a_inf && b_zero)) || (b_inf && a_zero);
	assign inf = !nan && (a_inf || b_inf);
	assign zero = (!nan && !inf) && (a_zero || b_zero);
	wire [M - 1:0] am = {1'b1, af};
	wire [M - 1:0] bm = {1'b1, bf};
	assign prod = am * bm;
	function automatic signed [EW - 1:0] sv2v_cast_27B61_signed;
		input reg signed [EW - 1:0] inp;
		sv2v_cast_27B61_signed = inp;
	endfunction
	assign top_exp = ($signed({{EW - EXP_BITS {1'b0}}, ae}) + $signed({{EW - EXP_BITS {1'b0}}, be})) - $signed(sv2v_cast_27B61_signed((2 * BIAS) - 1));
endmodule
module fp_align (
	prod,
	p_top,
	p_sign,
	p_zero,
	p_inf,
	p_nan,
	c,
	hi,
	lo,
	top_exp,
	hi_sign,
	lo_sign,
	sub,
	zero,
	inf,
	inf_sign,
	nan
);
	parameter EXP_BITS = 5;
	parameter MANT_BITS = 10;
	parameter W = (1 + EXP_BITS) + MANT_BITS;
	parameter M = MANT_BITS + 1;
	parameter EW = EXP_BITS + 4;
	parameter AW = (2 * M) + 3;
	input wire [(2 * M) - 1:0] prod;
	input wire signed [EW - 1:0] p_top;
	input wire p_sign;
	input wire p_zero;
	input wire p_inf;
	input wire p_nan;
	input wire [W - 1:0] c;
	output reg [AW - 1:0] hi;
	output reg [AW - 1:0] lo;
	output reg signed [EW - 1:0] top_exp;
	output reg hi_sign;
	output reg lo_sign;
	output wire sub;
	output wire zero;
	output wire inf;
	output wire inf_sign;
	output wire nan;
	localparam integer BIAS = (1 << (EXP_BITS - 1)) - 1;
	localparam integer EXP_ONE = (1 << EXP_BITS) - 1;
	localparam integer SW = $clog2(AW + 1);
	wire [EXP_BITS - 1:0] ce = c[W - 2-:EXP_BITS];
	wire [MANT_BITS - 1:0] cf = c[MANT_BITS - 1:0];
	wire c_sign = c[W - 1];
	wire c_zero = ce == 0;
	wire c_inf = (ce == EXP_ONE) && (cf == 0);
	wire c_nan = (ce == EXP_ONE) && (cf != 0);
	assign nan = (p_nan || c_nan) || ((p_inf && c_inf) && (p_sign != c_sign));
	assign inf = !nan && (p_inf || c_inf);
	assign inf_sign = (p_inf ? p_sign : c_sign);
	assign zero = p_zero && c_zero;
	assign sub = ((p_sign != c_sign) && !p_zero) && !c_zero;
	wire [AW - 1:0] p_w = {prod, 3'b000};
	wire [AW - 1:0] c_w = {1'b1, cf, {M {1'b0}}, 3'b000};
	function automatic signed [EW - 1:0] sv2v_cast_27B61_signed;
		input reg signed [EW - 1:0] inp;
		sv2v_cast_27B61_signed = inp;
	endfunction
	wire signed [EW - 1:0] c_top = $signed({{EW - EXP_BITS {1'b0}}, ce}) - $signed(sv2v_cast_27B61_signed(BIAS));
	wire signed [EW:0] d_pc = $signed({p_top[EW - 1], p_top}) - $signed({c_top[EW - 1], c_top});
	wire signed [EW:0] d_cp = $signed({c_top[EW - 1], c_top}) - $signed({p_top[EW - 1], p_top});
	wire p_high = !d_pc[EW];
	wire [EW:0] span = (p_high ? d_pc : d_cp);
	function automatic signed [SW - 1:0] sv2v_cast_2449B_signed;
		input reg signed [SW - 1:0] inp;
		sv2v_cast_2449B_signed = inp;
	endfunction
	wire [SW - 1:0] shift = (span >= AW ? sv2v_cast_2449B_signed(AW) : span[SW - 1:0]);
	wire [AW - 1:0] sh_in = (p_high ? c_w : p_w);
	wire [AW - 1:0] sh_out = sh_in >> shift;
	wire [AW - 1:0] lost_mask = ~({AW {1'b1}} << shift);
	wire sh_sticky = |(sh_in & lost_mask);
	always @(*)
		if (p_zero) begin
			hi = c_w;
			lo = {AW {1'b0}};
			top_exp = c_top;
			hi_sign = c_sign;
			lo_sign = p_sign;
		end
		else if (c_zero) begin
			hi = p_w;
			lo = {AW {1'b0}};
			top_exp = p_top;
			hi_sign = p_sign;
			lo_sign = c_sign;
		end
		else if (p_high) begin
			hi = p_w;
			lo = sh_out | {{AW - 1 {1'b0}}, sh_sticky};
			top_exp = p_top;
			hi_sign = p_sign;
			lo_sign = c_sign;
		end
		else begin
			hi = c_w;
			lo = sh_out | {{AW - 1 {1'b0}}, sh_sticky};
			top_exp = c_top;
			hi_sign = c_sign;
			lo_sign = p_sign;
		end
endmodule
module fp_addsub (
	hi,
	lo,
	in_top,
	hi_sign,
	lo_sign,
	sub,
	in_zero,
	in_inf,
	inf_sign,
	in_nan,
	mag,
	top_exp,
	sign,
	zero,
	inf,
	nan
);
	parameter EXP_BITS = 5;
	parameter MANT_BITS = 10;
	parameter M = MANT_BITS + 1;
	parameter EW = EXP_BITS + 4;
	parameter AW = (2 * M) + 3;
	input wire [AW - 1:0] hi;
	input wire [AW - 1:0] lo;
	input wire signed [EW - 1:0] in_top;
	input wire hi_sign;
	input wire lo_sign;
	input wire sub;
	input wire in_zero;
	input wire in_inf;
	input wire inf_sign;
	input wire in_nan;
	output reg [AW:0] mag;
	output wire signed [EW - 1:0] top_exp;
	output reg sign;
	output wire zero;
	output wire inf;
	output wire nan;
	wire [AW:0] sum = {1'b0, hi} + {1'b0, lo};
	wire [AW:0] d_hl = {1'b0, hi} - {1'b0, lo};
	wire [AW:0] d_lh = {1'b0, lo} - {1'b0, hi};
	wire equal = hi == lo;
	assign top_exp = in_top;
	assign nan = in_nan;
	assign inf = !in_nan && in_inf;
	assign zero = (!in_nan && !in_inf) && (in_zero || (sub && equal));
	always @(*) begin
		if (!sub) begin
			mag = sum;
			sign = hi_sign;
		end
		else if (!d_hl[AW]) begin
			mag = d_hl;
			sign = hi_sign;
		end
		else begin
			mag = d_lh;
			sign = lo_sign;
		end
		if (in_inf)
			sign = inf_sign;
		else if (in_zero)
			sign = hi_sign & lo_sign;
		else if (sub && equal)
			sign = 1'b0;
	end
endmodule
module fp_round (
	mag,
	top_exp,
	sign,
	zero,
	inf,
	nan,
	result
);
	parameter EXP_BITS = 5;
	parameter MANT_BITS = 10;
	parameter W = (1 + EXP_BITS) + MANT_BITS;
	parameter M = MANT_BITS + 1;
	parameter EW = EXP_BITS + 4;
	parameter AW = (2 * M) + 3;
	input wire [AW:0] mag;
	input wire signed [EW - 1:0] top_exp;
	input wire sign;
	input wire zero;
	input wire inf;
	input wire nan;
	output reg [W - 1:0] result;
	localparam integer BIAS = (1 << (EXP_BITS - 1)) - 1;
	localparam integer EXP_ONE = (1 << EXP_BITS) - 1;
	localparam integer EMIN = 1 - BIAS;
	localparam integer EMAX = (EXP_ONE - 1) - BIAS;
	localparam integer PW = 32;
	localparam integer NW = 5;
	reg [PW - 1:0] v;
	reg [NW - 1:0] nlz;
	always @(*) begin
		v = {mag, {(PW - AW) - 1 {1'b0}}};
		nlz = {NW {1'b0}};
		if (v[31:16] == 0) begin
			v = v << 16;
			nlz[4] = 1'b1;
		end
		if (v[31:24] == 0) begin
			v = v << 8;
			nlz[3] = 1'b1;
		end
		if (v[31:28] == 0) begin
			v = v << 4;
			nlz[2] = 1'b1;
		end
		if (v[31:30] == 0) begin
			v = v << 2;
			nlz[1] = 1'b1;
		end
		if (v[31] == 0) begin
			v = v << 1;
			nlz[0] = 1'b1;
		end
	end
	function automatic signed [((EW + 0) >= 0 ? EW + 1 : 1 - (EW + 0)) - 1:0] sv2v_cast_0BA7A_signed;
		input reg signed [((EW + 0) >= 0 ? EW + 1 : 1 - (EW + 0)) - 1:0] inp;
		sv2v_cast_0BA7A_signed = inp;
	endfunction
	wire signed [EW:0] exp_lead = ($signed({top_exp[EW - 1], top_exp}) + $signed(sv2v_cast_0BA7A_signed(1))) - $signed({{(EW + 1) - NW {1'b0}}, nlz});
	wire signed [EW:0] exp_up = exp_lead + $signed(sv2v_cast_0BA7A_signed(1));
	wire [M - 1:0] sig = v[PW - 1-:M];
	wire rbit = v[(PW - 1) - M];
	wire sticky = |v[(PW - 2) - M:0];
	wire up = rbit && (sticky || sig[0]);
	wire [M:0] sig_r = {1'b0, sig} + {{M {1'b0}}, up};
	wire carry = sig_r[M];
	wire [MANT_BITS - 1:0] frac = (carry ? {MANT_BITS {1'b0}} : sig_r[MANT_BITS - 1:0]);
	wire tiny = exp_lead < $signed(sv2v_cast_0BA7A_signed(EMIN));
	wire ovf_lead = exp_lead > $signed(sv2v_cast_0BA7A_signed(EMAX));
	wire ovf_up = exp_up > $signed(sv2v_cast_0BA7A_signed(EMAX));
	function automatic signed [EXP_BITS - 1:0] sv2v_cast_DBE99_signed;
		input reg signed [EXP_BITS - 1:0] inp;
		sv2v_cast_DBE99_signed = inp;
	endfunction
	wire [EXP_BITS - 1:0] ef_lead = sv2v_cast_DBE99_signed(exp_lead + $signed(sv2v_cast_0BA7A_signed(BIAS)));
	wire [EXP_BITS - 1:0] ef_up = sv2v_cast_DBE99_signed(exp_up + $signed(sv2v_cast_0BA7A_signed(BIAS)));
	always @(*)
		if (nan)
			result = {1'b0, {EXP_BITS {1'b1}}, 1'b1, {MANT_BITS - 1 {1'b0}}};
		else if (inf)
			result = {sign, {EXP_BITS {1'b1}}, {MANT_BITS {1'b0}}};
		else if (zero || tiny)
			result = {sign, {W - 1 {1'b0}}};
		else if ((carry ? ovf_up : ovf_lead))
			result = {sign, {EXP_BITS {1'b1}}, {MANT_BITS {1'b0}}};
		else
			result = {sign, (carry ? ef_up : ef_lead), frac};
endmodule
`default_nettype none
module fpx_align (
	prod,
	p_top,
	p_sign,
	p_zero,
	p_inf,
	p_nan,
	c,
	hi,
	lo,
	top_exp,
	hi_sign,
	lo_sign,
	sub,
	zero,
	inf,
	inf_sign,
	nan
);
	parameter IN_E = 5;
	parameter IN_M = 10;
	parameter ACC_E = 8;
	parameter ACC_M = 23;
	parameter Mi = IN_M + 1;
	parameter Ma = ACC_M + 1;
	parameter AW_P = (2 * Mi) + 3;
	parameter AW_A = Ma + 4;
	parameter AW = (AW_P > AW_A ? AW_P : AW_A);
	parameter EW = (IN_E > ACC_E ? IN_E : ACC_E) + 4;
	parameter CW = (1 + ACC_E) + ACC_M;
	input wire [(2 * Mi) - 1:0] prod;
	input wire signed [EW - 1:0] p_top;
	input wire p_sign;
	input wire p_zero;
	input wire p_inf;
	input wire p_nan;
	input wire [CW - 1:0] c;
	output reg [AW - 1:0] hi;
	output reg [AW - 1:0] lo;
	output reg signed [EW - 1:0] top_exp;
	output reg hi_sign;
	output reg lo_sign;
	output wire sub;
	output wire zero;
	output wire inf;
	output wire inf_sign;
	output wire nan;
	localparam integer BIAS = (1 << (ACC_E - 1)) - 1;
	localparam integer EXP_ONE = (1 << ACC_E) - 1;
	localparam integer SW = $clog2(AW + 1);
	wire [ACC_E - 1:0] ce = c[CW - 2-:ACC_E];
	wire [ACC_M - 1:0] cf = c[ACC_M - 1:0];
	wire c_sign = c[CW - 1];
	wire c_zero = ce == 0;
	wire c_inf = (ce == EXP_ONE) && (cf == 0);
	wire c_nan = (ce == EXP_ONE) && (cf != 0);
	assign nan = (p_nan || c_nan) || ((p_inf && c_inf) && (p_sign != c_sign));
	assign inf = !nan && (p_inf || c_inf);
	assign inf_sign = (p_inf ? p_sign : c_sign);
	assign zero = p_zero && c_zero;
	assign sub = ((p_sign != c_sign) && !p_zero) && !c_zero;
	wire [AW - 1:0] p_w = {prod, {AW - (2 * Mi) {1'b0}}};
	wire [AW - 1:0] c_w = {1'b1, cf, {AW - Ma {1'b0}}};
	function automatic signed [EW - 1:0] sv2v_cast_27B61_signed;
		input reg signed [EW - 1:0] inp;
		sv2v_cast_27B61_signed = inp;
	endfunction
	wire signed [EW - 1:0] c_top = $signed({{EW - ACC_E {1'b0}}, ce}) - $signed(sv2v_cast_27B61_signed(BIAS));
	wire signed [EW:0] d_pc = $signed({p_top[EW - 1], p_top}) - $signed({c_top[EW - 1], c_top});
	wire signed [EW:0] d_cp = $signed({c_top[EW - 1], c_top}) - $signed({p_top[EW - 1], p_top});
	wire p_high = !d_pc[EW];
	wire [EW:0] span = (p_high ? d_pc : d_cp);
	function automatic signed [SW - 1:0] sv2v_cast_2449B_signed;
		input reg signed [SW - 1:0] inp;
		sv2v_cast_2449B_signed = inp;
	endfunction
	wire [SW - 1:0] shift = (span >= AW ? sv2v_cast_2449B_signed(AW) : span[SW - 1:0]);
	wire [AW - 1:0] sh_in = (p_high ? c_w : p_w);
	wire [AW - 1:0] sh_out = sh_in >> shift;
	wire [AW - 1:0] lost_mask = ~({AW {1'b1}} << shift);
	wire sh_sticky = |(sh_in & lost_mask);
	always @(*)
		if (p_zero) begin
			hi = c_w;
			lo = {AW {1'b0}};
			top_exp = c_top;
			hi_sign = c_sign;
			lo_sign = p_sign;
		end
		else if (c_zero) begin
			hi = p_w;
			lo = {AW {1'b0}};
			top_exp = p_top;
			hi_sign = p_sign;
			lo_sign = c_sign;
		end
		else if (p_high) begin
			hi = p_w;
			lo = sh_out | {{AW - 1 {1'b0}}, sh_sticky};
			top_exp = p_top;
			hi_sign = p_sign;
			lo_sign = c_sign;
		end
		else begin
			hi = c_w;
			lo = sh_out | {{AW - 1 {1'b0}}, sh_sticky};
			top_exp = c_top;
			hi_sign = c_sign;
			lo_sign = p_sign;
		end
endmodule
module fpx_mul (
	a,
	b,
	prod,
	top_exp,
	sign,
	zero,
	inf,
	nan
);
	parameter EXP_BITS = 5;
	parameter MANT_BITS = 10;
	parameter W = (1 + EXP_BITS) + MANT_BITS;
	parameter M = MANT_BITS + 1;
	parameter EW = EXP_BITS + 4;
	parameter TRUNC_K = -1;
	parameter COMP = 0;
	input wire [W - 1:0] a;
	input wire [W - 1:0] b;
	output wire [(2 * M) - 1:0] prod;
	output wire signed [EW - 1:0] top_exp;
	output wire sign;
	output wire zero;
	output wire inf;
	output wire nan;
	localparam integer BIAS = (1 << (EXP_BITS - 1)) - 1;
	localparam integer EXP_ONE = (1 << EXP_BITS) - 1;
	wire [EXP_BITS - 1:0] ae = a[W - 2-:EXP_BITS];
	wire [EXP_BITS - 1:0] be = b[W - 2-:EXP_BITS];
	wire [MANT_BITS - 1:0] af = a[MANT_BITS - 1:0];
	wire [MANT_BITS - 1:0] bf = b[MANT_BITS - 1:0];
	wire a_zero = ae == 0;
	wire b_zero = be == 0;
	wire a_inf = (ae == EXP_ONE) && (af == 0);
	wire b_inf = (be == EXP_ONE) && (bf == 0);
	wire a_nan = (ae == EXP_ONE) && (af != 0);
	wire b_nan = (be == EXP_ONE) && (bf != 0);
	assign sign = a[W - 1] ^ b[W - 1];
	assign nan = ((a_nan || b_nan) || (a_inf && b_zero)) || (b_inf && a_zero);
	assign inf = !nan && (a_inf || b_inf);
	assign zero = (!nan && !inf) && (a_zero || b_zero);
	wire [M - 1:0] am = {1'b1, af};
	wire [M - 1:0] bm = {1'b1, bf};
	function automatic signed [(2 * M) - 1:0] sv2v_cast_355E1_signed;
		input reg signed [(2 * M) - 1:0] inp;
		sv2v_cast_355E1_signed = inp;
	endfunction
	generate
		if (TRUNC_K < 0) begin : g_mul
			assign prod = am * bm;
		end
		else begin : g_rows
			localparam [(2 * M) - 1:0] ONE = 1;
			localparam [(2 * M) - 1:0] KEEP = ~((ONE << TRUNC_K) - ONE);
			reg [(2 * M) - 1:0] s;
			integer i;
			always @(*) begin
				s = sv2v_cast_355E1_signed(COMP);
				for (i = 0; i < M; i = i + 1)
					s = s + ((({{M {1'b0}}, bm} << i) & {2 * M {am[i]}}) & KEEP);
			end
			assign prod = s;
		end
	endgenerate
	function automatic signed [EW - 1:0] sv2v_cast_27B61_signed;
		input reg signed [EW - 1:0] inp;
		sv2v_cast_27B61_signed = inp;
	endfunction
	assign top_exp = ($signed({{EW - EXP_BITS {1'b0}}, ae}) + $signed({{EW - EXP_BITS {1'b0}}, be})) - $signed(sv2v_cast_27B61_signed((2 * BIAS) - 1));
endmodule
`default_nettype none
module v3_pe_sf (
	clk,
	clk_w,
	clk_a,
	w_shift,
	w_swap,
	a_in,
	a_out,
	w_in,
	w_out,
	psum_in,
	psum_out
);
	parameter FRAC = 23;
	parameter ACC_W = 32;
	parameter TRUNC_K = -1;
	parameter COMP = 0;
	parameter CG = 0;
	input wire clk;
	input wire clk_w;
	input wire clk_a;
	input wire w_shift;
	input wire w_swap;
	input wire [15:0] a_in;
	output reg [15:0] a_out;
	input wire [15:0] w_in;
	output reg [15:0] w_out;
	input wire [ACC_W - 1:0] psum_in;
	output reg [ACC_W - 1:0] psum_out;
	reg [15:0] w_act;
	reg [FRAC - 1:0] p_mag;
	reg p_sign;
	wire [29:0] prod;
	function automatic signed [29:0] sv2v_cast_30_signed;
		input reg signed [29:0] inp;
		sv2v_cast_30_signed = inp;
	endfunction
	generate
		if (TRUNC_K < 0) begin : g_mul
			assign prod = a_out[14:0] * w_act[14:0];
		end
		else begin : g_rows
			localparam [29:0] KEEP = ~((30'd1 << TRUNC_K) - 30'd1);
			reg [29:0] s;
			integer i;
			always @(*) begin
				s = sv2v_cast_30_signed(COMP);
				for (i = 0; i < 15; i = i + 1)
					s = s + ((({15'b000000000000000, w_act[14:0]} << i) & {30 {a_out[i]}}) & KEEP);
			end
			assign prod = s;
		end
		if (CG) begin : g_cg
			always @(posedge clk_w) w_out <= w_in;
			always @(posedge clk_a) w_act <= w_out;
		end
		else begin : g_en
			always @(posedge clk) begin
				if (w_shift)
					w_out <= w_in;
				if (w_swap)
					w_act <= w_out;
			end
		end
	endgenerate
	wire signed [ACC_W:0] term = (p_sign ? -$signed({{(ACC_W + 1) - FRAC {1'b0}}, p_mag}) : $signed({{(ACC_W + 1) - FRAC {1'b0}}, p_mag}));
	wire signed [ACC_W:0] sum = $signed({psum_in[ACC_W - 1], psum_in}) + term;
	wire ovf = sum[ACC_W] ^ sum[ACC_W - 1];
	wire [ACC_W - 1:0] sat = (ovf ? {sum[ACC_W], {ACC_W - 1 {!sum[ACC_W]}}} : sum[ACC_W - 1:0]);
	always @(posedge clk) begin
		a_out <= a_in;
		p_mag <= prod[29-:FRAC];
		p_sign <= a_out[15] ^ w_act[15];
		psum_out <= sat;
	end
endmodule
module v3_pe_fp (
	clk,
	clk_w,
	clk_a,
	w_shift,
	w_swap,
	a_in,
	a_out,
	w_in,
	w_out,
	psum_in,
	psum_out
);
	parameter IN_E = 5;
	parameter IN_M = 10;
	parameter ACC_E = 8;
	parameter ACC_M = 23;
	parameter ALIGN_STAGE = 0;
	parameter TRUNC_K = -1;
	parameter COMP = 0;
	parameter CG = 0;
	parameter IW = (1 + IN_E) + IN_M;
	parameter CW = (1 + ACC_E) + ACC_M;
	input wire clk;
	input wire clk_w;
	input wire clk_a;
	input wire w_shift;
	input wire w_swap;
	input wire [IW - 1:0] a_in;
	output reg [IW - 1:0] a_out;
	input wire [IW - 1:0] w_in;
	output reg [IW - 1:0] w_out;
	input wire [CW - 1:0] psum_in;
	output reg [CW - 1:0] psum_out;
	localparam Mi = IN_M + 1;
	localparam Ma = ACC_M + 1;
	localparam AW_P = (2 * Mi) + 3;
	localparam AW_A = Ma + 4;
	localparam AW = (AW_P > AW_A ? AW_P : AW_A);
	localparam EW = (IN_E > ACC_E ? IN_E : ACC_E) + 4;
	reg [IW - 1:0] w_act;
	wire [(2 * Mi) - 1:0] mul_prod;
	wire signed [EW - 1:0] mul_top;
	wire mul_sign;
	wire mul_zero;
	wire mul_inf;
	wire mul_nan;
	fpx_mul #(
		.EXP_BITS(IN_E),
		.MANT_BITS(IN_M),
		.EW(EW),
		.TRUNC_K(TRUNC_K),
		.COMP(COMP)
	) u_mul(
		.a(a_out),
		.b(w_act),
		.prod(mul_prod),
		.top_exp(mul_top),
		.sign(mul_sign),
		.zero(mul_zero),
		.inf(mul_inf),
		.nan(mul_nan)
	);
	reg [(2 * Mi) - 1:0] p_prod;
	reg signed [EW - 1:0] p_top;
	reg p_sign;
	reg p_zero;
	reg p_inf;
	reg p_nan;
	wire [AW - 1:0] al_hi;
	wire [AW - 1:0] al_lo;
	wire signed [EW - 1:0] al_top;
	wire al_hi_sign;
	wire al_lo_sign;
	wire al_sub;
	wire al_zero;
	wire al_inf;
	wire al_inf_sign;
	wire al_nan;
	fpx_align #(
		.IN_E(IN_E),
		.IN_M(IN_M),
		.ACC_E(ACC_E),
		.ACC_M(ACC_M)
	) u_align(
		.prod(p_prod),
		.p_top(p_top),
		.p_sign(p_sign),
		.p_zero(p_zero),
		.p_inf(p_inf),
		.p_nan(p_nan),
		.c(psum_in),
		.hi(al_hi),
		.lo(al_lo),
		.top_exp(al_top),
		.hi_sign(al_hi_sign),
		.lo_sign(al_lo_sign),
		.sub(al_sub),
		.zero(al_zero),
		.inf(al_inf),
		.inf_sign(al_inf_sign),
		.nan(al_nan)
	);
	wire [AW - 1:0] ad_hi;
	wire [AW - 1:0] ad_lo;
	wire signed [EW - 1:0] ad_top;
	wire ad_hi_sign;
	wire ad_lo_sign;
	wire ad_sub;
	wire ad_zero;
	wire ad_inf;
	wire ad_inf_sign;
	wire ad_nan;
	generate
		if (ALIGN_STAGE) begin : g_align_reg
			reg [AW - 1:0] r_hi;
			reg [AW - 1:0] r_lo;
			reg signed [EW - 1:0] r_top;
			reg r_hi_sign;
			reg r_lo_sign;
			reg r_sub;
			reg r_zero;
			reg r_inf;
			reg r_inf_sign;
			reg r_nan;
			always @(posedge clk) begin
				r_hi <= al_hi;
				r_lo <= al_lo;
				r_top <= al_top;
				{r_hi_sign, r_lo_sign, r_sub, r_zero, r_inf, r_inf_sign, r_nan} <= {al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan};
			end
			assign {ad_hi, ad_lo, ad_top} = {r_hi, r_lo, r_top};
			assign {ad_hi_sign, ad_lo_sign, ad_sub, ad_zero, ad_inf, ad_inf_sign, ad_nan} = {r_hi_sign, r_lo_sign, r_sub, r_zero, r_inf, r_inf_sign, r_nan};
		end
		else begin : g_align_comb
			assign {ad_hi, ad_lo, ad_top} = {al_hi, al_lo, al_top};
			assign {ad_hi_sign, ad_lo_sign, ad_sub, ad_zero, ad_inf, ad_inf_sign, ad_nan} = {al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan};
		end
	endgenerate
	wire [AW:0] add_mag;
	wire signed [EW - 1:0] add_top;
	wire add_sign;
	wire add_zero;
	wire add_inf;
	wire add_nan;
	fp_addsub #(
		.EXP_BITS(ACC_E),
		.MANT_BITS(ACC_M),
		.EW(EW),
		.AW(AW)
	) u_addsub(
		.hi(ad_hi),
		.lo(ad_lo),
		.in_top(ad_top),
		.hi_sign(ad_hi_sign),
		.lo_sign(ad_lo_sign),
		.sub(ad_sub),
		.in_zero(ad_zero),
		.in_inf(ad_inf),
		.inf_sign(ad_inf_sign),
		.in_nan(ad_nan),
		.mag(add_mag),
		.top_exp(add_top),
		.sign(add_sign),
		.zero(add_zero),
		.inf(add_inf),
		.nan(add_nan)
	);
	reg [AW:0] s_mag;
	reg signed [EW - 1:0] s_top;
	reg s_sign;
	reg s_zero;
	reg s_inf;
	reg s_nan;
	wire [CW - 1:0] rounded;
	fp_round #(
		.EXP_BITS(ACC_E),
		.MANT_BITS(ACC_M),
		.EW(EW),
		.AW(AW)
	) u_round(
		.mag(s_mag),
		.top_exp(s_top),
		.sign(s_sign),
		.zero(s_zero),
		.inf(s_inf),
		.nan(s_nan),
		.result(rounded)
	);
	generate
		if (CG) begin : g_cg
			always @(posedge clk_w) w_out <= w_in;
			always @(posedge clk_a) w_act <= w_out;
		end
		else begin : g_en
			always @(posedge clk) begin
				if (w_shift)
					w_out <= w_in;
				if (w_swap)
					w_act <= w_out;
			end
		end
	endgenerate
	always @(posedge clk) begin
		a_out <= a_in;
		p_prod <= mul_prod;
		p_top <= mul_top;
		{p_sign, p_zero, p_inf, p_nan} <= {mul_sign, mul_zero, mul_inf, mul_nan};
		s_mag <= add_mag;
		s_top <= add_top;
		{s_sign, s_zero, s_inf, s_nan} <= {add_sign, add_zero, add_inf, add_nan};
		psum_out <= rounded;
	end
endmodule
`default_nettype none
module v3_block (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	parameter N = 8;
	parameter FMT = 0;
	parameter FRAC = 23;
	parameter ACC_W = 32;
	parameter IN_E = 5;
	parameter IN_M = 10;
	parameter ACC_E = 8;
	parameter ACC_M = 23;
	parameter ALIGN_STAGE = 0;
	parameter TRUNC_K = -1;
	parameter COMP = 0;
	parameter CG = 0;
	parameter IW = (FMT == 0 ? 16 : (1 + IN_E) + IN_M);
	parameter CW = (FMT == 0 ? ACC_W : (1 + ACC_E) + ACC_M);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [(N * IW) - 1:0] a_west;
	input wire [(N * IW) - 1:0] w_north;
	input wire [(N * CW) - 1:0] psum_north;
	output reg [(N * IW) - 1:0] a_east;
	output reg [(N * CW) - 1:0] psum_south;
	reg shift_q;
	reg swap_q;
	reg [(N * IW) - 1:0] a_q;
	reg [(N * IW) - 1:0] w_q;
	reg [(N * CW) - 1:0] p_q;
	wire [IW - 1:0] a_bus [0:N - 1][0:N];
	wire [IW - 1:0] w_bus [0:N][0:N - 1];
	wire [CW - 1:0] p_bus [0:N][0:N - 1];
	wire [N - 1:0] gclk_w;
	wire [N - 1:0] gclk_a;
	genvar _gv_r_1;
	genvar _gv_c_1;
	generate
		for (_gv_r_1 = 0; _gv_r_1 < N; _gv_r_1 = _gv_r_1 + 1) begin : g_gate
			localparam r = _gv_r_1;
			if (CG) begin : g_on
				reg en_w_n;
				reg en_a_n;
				always @(negedge clk) begin
					en_w_n <= shift_q;
					en_a_n <= swap_q;
				end
				assign gclk_w[r] = clk & en_w_n;
				assign gclk_a[r] = clk & en_a_n;
			end
			else begin : g_off
				assign gclk_w[r] = clk;
				assign gclk_a[r] = clk;
			end
		end
		for (_gv_r_1 = 0; _gv_r_1 < N; _gv_r_1 = _gv_r_1 + 1) begin : g_west
			localparam r = _gv_r_1;
			assign a_bus[r][0] = a_q[r * IW+:IW];
		end
		for (_gv_c_1 = 0; _gv_c_1 < N; _gv_c_1 = _gv_c_1 + 1) begin : g_north
			localparam c = _gv_c_1;
			assign w_bus[0][c] = w_q[c * IW+:IW];
			assign p_bus[0][c] = p_q[c * CW+:CW];
		end
		for (_gv_r_1 = 0; _gv_r_1 < N; _gv_r_1 = _gv_r_1 + 1) begin : g_row
			localparam r = _gv_r_1;
			for (_gv_c_1 = 0; _gv_c_1 < N; _gv_c_1 = _gv_c_1 + 1) begin : g_col
				localparam c = _gv_c_1;
				if (FMT == 0) begin : g_sf
					v3_pe_sf #(
						.FRAC(FRAC),
						.ACC_W(ACC_W),
						.TRUNC_K(TRUNC_K),
						.COMP(COMP),
						.CG(CG)
					) u_pe(
						.clk(clk),
						.clk_w(gclk_w[r]),
						.clk_a(gclk_a[r]),
						.w_shift(shift_q),
						.w_swap(swap_q),
						.a_in(a_bus[r][c]),
						.a_out(a_bus[r][c + 1]),
						.w_in(w_bus[r][c]),
						.w_out(w_bus[r + 1][c]),
						.psum_in(p_bus[r][c]),
						.psum_out(p_bus[r + 1][c])
					);
				end
				else begin : g_fp
					v3_pe_fp #(
						.IN_E(IN_E),
						.IN_M(IN_M),
						.ACC_E(ACC_E),
						.ACC_M(ACC_M),
						.ALIGN_STAGE(ALIGN_STAGE),
						.TRUNC_K(TRUNC_K),
						.COMP(COMP),
						.CG(CG)
					) u_pe(
						.clk(clk),
						.clk_w(gclk_w[r]),
						.clk_a(gclk_a[r]),
						.w_shift(shift_q),
						.w_swap(swap_q),
						.a_in(a_bus[r][c]),
						.a_out(a_bus[r][c + 1]),
						.w_in(w_bus[r][c]),
						.w_out(w_bus[r + 1][c]),
						.psum_in(p_bus[r][c]),
						.psum_out(p_bus[r + 1][c])
					);
				end
			end
		end
	endgenerate
	integer i;
	always @(posedge clk) begin
		shift_q <= w_shift;
		swap_q <= w_swap;
		a_q <= a_west;
		w_q <= w_north;
		p_q <= psum_north;
		for (i = 0; i < N; i = i + 1)
			begin
				a_east[i * IW+:IW] <= a_bus[i][N];
				psum_south[i * CW+:CW] <= p_bus[N][i];
			end
	end
endmodule
`default_nettype none
module blk_sf16_sat16 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [127:0] psum_north;
	output wire [127:0] a_east;
	output wire [127:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(15),
		.ACC_W(16)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf24 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(19),
		.ACC_W(24)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf32 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [255:0] psum_north;
	output wire [127:0] a_east;
	output wire [255:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(23),
		.ACC_W(32)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_fp16_fp16 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [127:0] psum_north;
	output wire [127:0] a_east;
	output wire [127:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(5),
		.IN_M(10),
		.ACC_E(5),
		.ACC_M(10)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_fp16_fp24 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(5),
		.IN_M(10),
		.ACC_E(8),
		.ACC_M(15)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_fp16_fp32 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [255:0] psum_north;
	output wire [127:0] a_east;
	output wire [255:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(5),
		.IN_M(10),
		.ACC_E(8),
		.ACC_M(23)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_bf16_bf16 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [127:0] psum_north;
	output wire [127:0] a_east;
	output wire [127:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(8),
		.IN_M(7),
		.ACC_E(8),
		.ACC_M(7)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_bf16_fp24 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(8),
		.IN_M(7),
		.ACC_E(8),
		.ACC_M(15)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_bf16_fp32 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [255:0] psum_north;
	output wire [127:0] a_east;
	output wire [255:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(8),
		.IN_M(7),
		.ACC_E(8),
		.ACC_M(23)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_fp16_fp16_a (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [127:0] psum_north;
	output wire [127:0] a_east;
	output wire [127:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(5),
		.IN_M(10),
		.ACC_E(5),
		.ACC_M(10),
		.ALIGN_STAGE(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_fp16_fp24_a (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(5),
		.IN_M(10),
		.ACC_E(8),
		.ACC_M(15),
		.ALIGN_STAGE(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_fp16_fp32_a (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [255:0] psum_north;
	output wire [127:0] a_east;
	output wire [255:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(5),
		.IN_M(10),
		.ACC_E(8),
		.ACC_M(23),
		.ALIGN_STAGE(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_bf16_bf16_a (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [127:0] psum_north;
	output wire [127:0] a_east;
	output wire [127:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(8),
		.IN_M(7),
		.ACC_E(8),
		.ACC_M(7),
		.ALIGN_STAGE(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_bf16_fp24_a (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(8),
		.IN_M(7),
		.ACC_E(8),
		.ACC_M(15),
		.ALIGN_STAGE(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_bf16_fp32_a (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [255:0] psum_north;
	output wire [127:0] a_east;
	output wire [255:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(8),
		.IN_M(7),
		.ACC_E(8),
		.ACC_M(23),
		.ALIGN_STAGE(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf24_m (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(19),
		.ACC_W(24),
		.TRUNC_K(0)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf24_t (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(19),
		.ACC_W(24),
		.TRUNC_K(9),
		.COMP(1024)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf24_tg (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(19),
		.ACC_W(24),
		.TRUNC_K(9),
		.COMP(1024),
		.CG(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf28 (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [223:0] psum_north;
	output wire [127:0] a_east;
	output wire [223:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(23),
		.ACC_W(28)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf28_t (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [223:0] psum_north;
	output wire [127:0] a_east;
	output wire [223:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(23),
		.ACC_W(28),
		.TRUNC_K(6),
		.COMP(80)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf28_tg (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [223:0] psum_north;
	output wire [127:0] a_east;
	output wire [223:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(23),
		.ACC_W(28),
		.TRUNC_K(6),
		.COMP(80),
		.CG(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf32_m (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [255:0] psum_north;
	output wire [127:0] a_east;
	output wire [255:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(23),
		.ACC_W(32),
		.TRUNC_K(0)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf32_t (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [255:0] psum_north;
	output wire [127:0] a_east;
	output wire [255:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(23),
		.ACC_W(32),
		.TRUNC_K(6),
		.COMP(80)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_sf16_sf32_tg (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [255:0] psum_north;
	output wire [127:0] a_east;
	output wire [255:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(0),
		.FRAC(23),
		.ACC_W(32),
		.TRUNC_K(6),
		.COMP(80),
		.CG(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_fp16_fp24_a_m (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(5),
		.IN_M(10),
		.ACC_E(8),
		.ACC_M(15),
		.ALIGN_STAGE(1),
		.TRUNC_K(0)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_fp16_fp24_a_t (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(5),
		.IN_M(10),
		.ACC_E(8),
		.ACC_M(15),
		.ALIGN_STAGE(1),
		.TRUNC_K(4),
		.COMP(12)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_fp16_fp24_a_tg (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(5),
		.IN_M(10),
		.ACC_E(8),
		.ACC_M(15),
		.ALIGN_STAGE(1),
		.TRUNC_K(4),
		.COMP(12),
		.CG(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule
module blk_bf16_fp24_a_g (
	clk,
	w_shift,
	w_swap,
	a_west,
	w_north,
	psum_north,
	a_east,
	psum_south
);
	input wire clk;
	input wire w_shift;
	input wire w_swap;
	input wire [127:0] a_west;
	input wire [127:0] w_north;
	input wire [191:0] psum_north;
	output wire [127:0] a_east;
	output wire [191:0] psum_south;
	v3_block #(
		.N(8),
		.FMT(1),
		.IN_E(8),
		.IN_M(7),
		.ACC_E(8),
		.ACC_M(15),
		.ALIGN_STAGE(1),
		.CG(1)
	) u_blk(
		.clk(clk),
		.w_shift(w_shift),
		.w_swap(w_swap),
		.a_west(a_west),
		.w_north(w_north),
		.psum_north(psum_north),
		.a_east(a_east),
		.psum_south(psum_south)
	);
endmodule