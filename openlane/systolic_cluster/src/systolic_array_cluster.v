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
					.clear_acc(clear_acc),
					.load_weight(load_weights),
					.compute_enable(compute_enable),
					.a_in(a_wires[row][col]),
					.b_in(b_wires[row][col]),
					.a_out(a_wires[row][col + 1]),
					.b_out(b_wires[row + 1][col]),
					.acc_out(results[((row * ARRAY_SIZE) + col) * DATA_BITS+:DATA_BITS])
				);
			end
		end
	endgenerate
	reg ready_reg;
	assign ready = ready_reg;
	always @(posedge clk)
		if (reset)
			ready_reg <= 1'b1;
		else if (enable)
			ready_reg <= ~compute_enable;
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
	genvar _gv_arr_1;
	generate
		for (_gv_arr_1 = 0; _gv_arr_1 < NUM_ARRAYS; _gv_arr_1 = _gv_arr_1 + 1) begin : array_ctrl
			localparam arr = _gv_arr_1;
			assign array_clear_acc[arr] = (broadcast_mode ? clear_acc : (array_select == arr ? clear_acc : 1'b0));
			assign array_load_weights[arr] = (broadcast_mode ? load_weights : (array_select == arr ? load_weights : 1'b0));
			assign array_compute_enable[arr] = (broadcast_mode ? compute_enable : (array_select == arr ? compute_enable : 1'b0));
		end
		for (_gv_arr_1 = 0; _gv_arr_1 < NUM_ARRAYS; _gv_arr_1 = _gv_arr_1 + 1) begin : arrays
			localparam arr = _gv_arr_1;
			systolic_array #(
				.DATA_BITS(DATA_BITS),
				.ARRAY_SIZE(ARRAY_SIZE)
			) array_inst(
				.clk(clk),
				.reset(reset),
				.enable(enable),
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