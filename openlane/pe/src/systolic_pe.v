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
	parameter ACC_BITS = 24;
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
	localparam [DATA_BITS - 1:0] Q115_MAX = 16'h7fff;
	localparam [DATA_BITS - 1:0] Q115_MIN = 16'h8000;
	localparam [31:0] MAC_PIPE_LATENCY = 2;
	reg [DATA_BITS - 1:0] weight_reg;
	reg signed [ACC_BITS - 1:0] accumulator;
	wire sign_a_s0 = a_in[15];
	wire sign_w_s0 = weight_reg[15];
	wire sign_product_s0 = sign_a_s0 ^ sign_w_s0;
	wire [14:0] mantissa_a_s0 = (sign_a_s0 ? ~a_in[14:0] + 1'b1 : a_in[14:0]);
	wire [14:0] mantissa_w_s0 = (sign_w_s0 ? ~weight_reg[14:0] + 1'b1 : weight_reg[14:0]);
	reg valid_s0;
	reg sign_product_s0_r;
	reg [14:0] mantissa_a_s0_r;
	reg [14:0] mantissa_w_s0_r;
	wire [29:0] product_unsigned_s1 = mantissa_a_s0_r * mantissa_w_s0_r;
	wire [14:0] product_mantissa_s1 = product_unsigned_s1[29:15];
	reg valid_s1;
	reg sign_product_s1_r;
	reg [14:0] product_mantissa_s1_r;
	wire [DATA_BITS - 1:0] product_unsigned_16_s2 = {1'b0, product_mantissa_s1_r};
	wire signed [DATA_BITS - 1:0] product_signed_s2 = (sign_product_s1_r ? -$signed(product_unsigned_16_s2) : $signed(product_unsigned_16_s2));
	wire signed [ACC_BITS - 1:0] product_extended_s2 = {{ACC_BITS - DATA_BITS {product_signed_s2[DATA_BITS - 1]}}, product_signed_s2};
	wire signed [ACC_BITS - 1:0] acc_sum_s2 = accumulator + product_extended_s2;
	wire signed [ACC_BITS - 1:0] acc_shifted = accumulator;
	wire sat_positive = accumulator > $signed({{ACC_BITS - DATA_BITS {1'b0}}, Q115_MAX});
	wire sat_negative = accumulator < $signed({{ACC_BITS - DATA_BITS {1'b1}}, Q115_MIN});
	assign acc_out = (sat_positive ? Q115_MAX : (sat_negative ? Q115_MIN : accumulator[DATA_BITS - 1:0]));
	always @(posedge clk)
		if (reset) begin
			a_out <= {DATA_BITS {1'b0}};
			b_out <= {DATA_BITS {1'b0}};
			weight_reg <= {DATA_BITS {1'b0}};
			accumulator <= {ACC_BITS {1'b0}};
			valid_s0 <= 1'b0;
			valid_s1 <= 1'b0;
			sign_product_s0_r <= 1'b0;
			mantissa_a_s0_r <= 15'b000000000000000;
			mantissa_w_s0_r <= 15'b000000000000000;
			sign_product_s1_r <= 1'b0;
			product_mantissa_s1_r <= 15'b000000000000000;
		end
		else if (enable) begin
			a_out <= a_in;
			b_out <= b_in;
			if (load_weight)
				weight_reg <= b_in;
			if (clear_acc) begin
				accumulator <= {ACC_BITS {1'b0}};
				valid_s0 <= 1'b0;
				valid_s1 <= 1'b0;
			end
			else begin
				valid_s0 <= compute_enable;
				sign_product_s0_r <= sign_product_s0;
				mantissa_a_s0_r <= mantissa_a_s0;
				mantissa_w_s0_r <= mantissa_w_s0;
				valid_s1 <= valid_s0;
				sign_product_s1_r <= sign_product_s0_r;
				product_mantissa_s1_r <= product_mantissa_s1;
				if (valid_s1)
					accumulator <= acc_sum_s2;
			end
		end
endmodule