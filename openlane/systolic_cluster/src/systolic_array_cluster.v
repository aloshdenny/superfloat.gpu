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
`default_nettype none
module systolic_array (
	clk,
	reset,
	enable,
	clear_acc,
	load_weights,
	compute_enable,
	a_inputs,
	b_inputs,
	results,
	ready
);
	parameter DATA_BITS = 16;
	parameter ARRAY_SIZE = 4;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire clear_acc;
	input wire load_weights;
	input wire compute_enable;
	input wire signed [(ARRAY_SIZE * DATA_BITS) - 1:0] a_inputs;
	input wire signed [(ARRAY_SIZE * DATA_BITS) - 1:0] b_inputs;
	output wire [((ARRAY_SIZE * ARRAY_SIZE) * DATA_BITS) - 1:0] results;
	output wire ready;
	wire signed [DATA_BITS - 1:0] a_wires [ARRAY_SIZE - 1:0][ARRAY_SIZE:0];
	wire signed [DATA_BITS - 1:0] b_wires [ARRAY_SIZE:0][ARRAY_SIZE - 1:0];
	wire [ARRAY_SIZE - 1:0] row_clear_acc;
	wire [ARRAY_SIZE - 1:0] row_load_weight;
	wire [ARRAY_SIZE - 1:0] row_compute_enable;
	assign row_clear_acc = {ARRAY_SIZE {clear_acc}};
	assign row_load_weight = {ARRAY_SIZE {load_weights}};
	assign row_compute_enable = {ARRAY_SIZE {compute_enable}};
	genvar _gv_row_1;
	genvar _gv_col_1;
	generate
		for (_gv_row_1 = 0; _gv_row_1 < ARRAY_SIZE; _gv_row_1 = _gv_row_1 + 1) begin : a_input_connect
			localparam row = _gv_row_1;
			assign a_wires[row][0] = a_inputs[row * DATA_BITS+:DATA_BITS];
		end
		for (_gv_col_1 = 0; _gv_col_1 < ARRAY_SIZE; _gv_col_1 = _gv_col_1 + 1) begin : b_input_connect
			localparam col = _gv_col_1;
			assign b_wires[0][col] = b_inputs[col * DATA_BITS+:DATA_BITS];
		end
		for (_gv_row_1 = 0; _gv_row_1 < ARRAY_SIZE; _gv_row_1 = _gv_row_1 + 1) begin : pe_rows
			localparam row = _gv_row_1;
			for (_gv_col_1 = 0; _gv_col_1 < ARRAY_SIZE; _gv_col_1 = _gv_col_1 + 1) begin : pe_cols
				localparam col = _gv_col_1;
				systolic_pe #(.DATA_BITS(DATA_BITS)) pe_inst(
					.clk(clk),
					.reset(reset),
					.enable(enable),
					.clear_acc(row_clear_acc[row]),
					.load_weight(row_load_weight[row]),
					.compute_enable(row_compute_enable[row]),
					.a_in(a_wires[row][col]),
					.b_in(b_wires[row][col]),
					.a_out(a_wires[row][col + 1]),
					.b_out(b_wires[row + 1][col]),
					.acc_out(results[((row * ARRAY_SIZE) + col) * DATA_BITS+:DATA_BITS])
				);
			end
		end
	endgenerate
	assign ready = ~compute_enable;
endmodule
`default_nettype none
module systolic_array_cluster (
	clk,
	reset,
	enable,
	array_select,
	clear_acc,
	load_weights,
	compute_enable,
	broadcast_mode,
	a_inputs,
	b_inputs,
	results,
	ready,
	all_ready
);
	parameter DATA_BITS = 16;
	parameter ARRAY_SIZE = 8;
	parameter NUM_ARRAYS = 8;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [$clog2(NUM_ARRAYS) - 1:0] array_select;
	input wire clear_acc;
	input wire load_weights;
	input wire compute_enable;
	input wire broadcast_mode;
	input wire signed [(ARRAY_SIZE * DATA_BITS) - 1:0] a_inputs;
	input wire signed [(ARRAY_SIZE * DATA_BITS) - 1:0] b_inputs;
	output wire [((ARRAY_SIZE * ARRAY_SIZE) * DATA_BITS) - 1:0] results;
	output wire ready;
	output wire [NUM_ARRAYS - 1:0] all_ready;
	wire [((ARRAY_SIZE * ARRAY_SIZE) * DATA_BITS) - 1:0] array_results [NUM_ARRAYS - 1:0];
	wire [NUM_ARRAYS - 1:0] array_ready;
	wire [NUM_ARRAYS - 1:0] array_clear_acc;
	wire [NUM_ARRAYS - 1:0] array_load_weights;
	wire [NUM_ARRAYS - 1:0] array_compute_enable;
	wire [NUM_ARRAYS - 1:0] array_selected;
	wire [NUM_ARRAYS - 1:0] array_enable;
	reg [NUM_ARRAYS - 1:0] compute_enable_d1;
	reg [NUM_ARRAYS - 1:0] compute_enable_d2;
	genvar _gv_arr_1;
	generate
		for (_gv_arr_1 = 0; _gv_arr_1 < NUM_ARRAYS; _gv_arr_1 = _gv_arr_1 + 1) begin : array_ctrl
			localparam arr = _gv_arr_1;
			assign array_selected[arr] = (broadcast_mode ? 1'b1 : array_select == arr);
			assign array_clear_acc[arr] = (broadcast_mode ? clear_acc : (array_select == arr ? clear_acc : 1'b0));
			assign array_load_weights[arr] = (broadcast_mode ? load_weights : (array_select == arr ? load_weights : 1'b0));
			assign array_compute_enable[arr] = (broadcast_mode ? compute_enable : (array_select == arr ? compute_enable : 1'b0));
			assign array_enable[arr] = (enable && array_selected[arr]) && ((((array_clear_acc[arr] | array_load_weights[arr]) | array_compute_enable[arr]) | compute_enable_d1[arr]) | compute_enable_d2[arr]);
		end
	endgenerate
	always @(posedge clk)
		if (reset) begin
			compute_enable_d1 <= {NUM_ARRAYS {1'b0}};
			compute_enable_d2 <= {NUM_ARRAYS {1'b0}};
		end
		else if (enable) begin
			compute_enable_d2 <= compute_enable_d1;
			compute_enable_d1 <= array_compute_enable;
		end
	generate
		for (_gv_arr_1 = 0; _gv_arr_1 < NUM_ARRAYS; _gv_arr_1 = _gv_arr_1 + 1) begin : arrays
			localparam arr = _gv_arr_1;
			systolic_array #(
				.DATA_BITS(DATA_BITS),
				.ARRAY_SIZE(ARRAY_SIZE)
			) array_inst(
				.clk(clk),
				.reset(reset),
				.enable(array_enable[arr]),
				.clear_acc(array_clear_acc[arr]),
				.load_weights(array_load_weights[arr]),
				.compute_enable(array_compute_enable[arr]),
				.a_inputs(a_inputs),
				.b_inputs(b_inputs),
				.results(array_results[arr]),
				.ready(array_ready[arr])
			);
		end
	endgenerate
	genvar _gv_row_2;
	genvar _gv_col_2;
	generate
		for (_gv_row_2 = 0; _gv_row_2 < ARRAY_SIZE; _gv_row_2 = _gv_row_2 + 1) begin : result_row
			localparam row = _gv_row_2;
			for (_gv_col_2 = 0; _gv_col_2 < ARRAY_SIZE; _gv_col_2 = _gv_col_2 + 1) begin : result_col
				localparam col = _gv_col_2;
				assign results[((row * ARRAY_SIZE) + col) * DATA_BITS+:DATA_BITS] = array_results[array_select][((row * ARRAY_SIZE) + col) * DATA_BITS+:DATA_BITS];
			end
		end
	endgenerate
	assign ready = array_ready[array_select];
	assign all_ready = array_ready;
endmodule