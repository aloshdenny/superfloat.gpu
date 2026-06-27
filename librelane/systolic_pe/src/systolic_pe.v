`default_nettype none
module systolic_pe (
	clk,
	reset,
	enable,
	clear_acc,
	load_weight,
	compute_enable,
	a_in,
	b_in,
	a_out,
	b_out,
	acc_out
);
	parameter DATA_BITS = 16;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire clear_acc;
	input wire load_weight;
	input wire compute_enable;
	input wire [DATA_BITS - 1:0] a_in;
	input wire [DATA_BITS - 1:0] b_in;
	output reg [DATA_BITS - 1:0] a_out;
	output reg [DATA_BITS - 1:0] b_out;
	output wire [DATA_BITS - 1:0] acc_out;
	wire [DATA_BITS - 1:0] a_canon = (a_in == 16'h8000 ? 16'h0000 : a_in);
	wire [DATA_BITS - 1:0] b_canon = (b_in == 16'h8000 ? 16'h0000 : b_in);
	reg r2_sign;
	reg [14:0] r2_mantissa;
	reg valid_s0;
	reg [14:0] r3_prod_mant;
	reg r3_prod_sign;
	reg valid_s1;
	reg signed [15:0] r4_acc;
	wire s1_sign_a = a_out[15];
	wire [14:0] s1_mant_a = a_out[14:0];
	wire [29:0] s1_prod_wide = s1_mant_a * r2_mantissa;
	wire [14:0] s1_prod_mant = s1_prod_wide[29:15];
	wire s1_sign_prod = s1_sign_a ^ r2_sign;
	wire signed [16:0] s2_acc_ext = {r4_acc[15], r4_acc};
	wire signed [16:0] s2_prod_ext = {2'b00, r3_prod_mant};
	wire signed [16:0] s2_sum_wide = (r3_prod_sign ? s2_acc_ext - s2_prod_ext : s2_acc_ext + s2_prod_ext);
	wire s2_overflow = s2_sum_wide[16] != s2_sum_wide[15];
	wire s2_neg_zero = s2_sum_wide[15:0] == 16'h8000;
	localparam signed [15:0] SAT_MAX = 16'sh7fff;
	localparam signed [15:0] SAT_MIN = 16'sh8001;
	wire signed [15:0] s2_sat = (s2_overflow || s2_neg_zero ? (s2_sum_wide[16] ? SAT_MIN : SAT_MAX) : s2_sum_wide[15:0]);
	function automatic [14:0] sv2v_cast_15;
		input reg [14:0] inp;
		sv2v_cast_15 = inp;
	endfunction
	wire [14:0] acc_abs = (r4_acc[15] ? sv2v_cast_15(-r4_acc[15:0]) : r4_acc[14:0]);
	assign acc_out = {r4_acc[15], acc_abs};
	always @(posedge clk)
		if (reset) begin
			a_out <= {DATA_BITS {1'b0}};
			b_out <= {DATA_BITS {1'b0}};
			r2_sign <= 1'b0;
			r2_mantissa <= 15'b000000000000000;
			r3_prod_mant <= 15'b000000000000000;
			r3_prod_sign <= 1'b0;
			r4_acc <= 16'sb0000000000000000;
			valid_s0 <= 1'b0;
			valid_s1 <= 1'b0;
		end
		else if (enable) begin
			a_out <= a_canon;
			b_out <= b_canon;
			if (load_weight) begin
				r2_sign <= b_canon[15];
				r2_mantissa <= b_canon[14:0];
			end
			if (clear_acc) begin
				r3_prod_mant <= 15'b000000000000000;
				r3_prod_sign <= 1'b0;
				r4_acc <= 16'sb0000000000000000;
				valid_s0 <= 1'b0;
				valid_s1 <= 1'b0;
			end
			else begin
				valid_s0 <= compute_enable;
				valid_s1 <= valid_s0;
				r3_prod_mant <= s1_prod_mant;
				r3_prod_sign <= s1_sign_prod;
				if (valid_s1)
					r4_acc <= s2_sat;
			end
		end
endmodule