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
	reg [DATA_BITS - 1:0] weight_reg;
	reg signed [ACC_BITS - 1:0] accumulator;
	wire sign_a = a_in[15];
	wire sign_w = weight_reg[15];
	wire sign_product = sign_a ^ sign_w;
	wire [14:0] mantissa_a = (sign_a ? ~a_in[14:0] + 1'b1 : a_in[14:0]);
	wire [14:0] mantissa_w = (sign_w ? ~weight_reg[14:0] + 1'b1 : weight_reg[14:0]);
	wire [29:0] product_unsigned = mantissa_a * mantissa_w;
	wire [14:0] product_mantissa = product_unsigned[29:15];
	wire [DATA_BITS - 1:0] product_unsigned_16 = {1'b0, product_mantissa};
	wire signed [DATA_BITS - 1:0] product_signed = (sign_product ? -$signed(product_unsigned_16) : $signed(product_unsigned_16));
	wire signed [ACC_BITS - 1:0] product_extended = {{ACC_BITS - DATA_BITS {product_signed[DATA_BITS - 1]}}, product_signed};
	wire signed [ACC_BITS - 1:0] acc_sum = accumulator + product_extended;
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
		end
		else if (enable) begin
			a_out <= a_in;
			b_out <= b_in;
			if (load_weight)
				weight_reg <= b_in;
			if (clear_acc)
				accumulator <= {ACC_BITS {1'b0}};
			else if (compute_enable)
				accumulator <= acc_sum;
		end
endmodule