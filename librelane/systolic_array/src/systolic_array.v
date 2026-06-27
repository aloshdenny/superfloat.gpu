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
`default_nettype none
module systolic_array (
	clk,
	reset,
	enable,
	clear_acc,
	load_weights,
	compute_enable,
	a_inputs_flat,
	b_inputs_flat,
	results_flat,
	ready
);
	parameter DATA_BITS = 16;
	parameter ARRAY_SIZE = 2;
	parameter PIPE_INTERVAL = ARRAY_SIZE;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire clear_acc;
	input wire load_weights;
	input wire compute_enable;
	input wire signed [(DATA_BITS * ARRAY_SIZE) - 1:0] a_inputs_flat;
	input wire signed [(DATA_BITS * ARRAY_SIZE) - 1:0] b_inputs_flat;
	output wire [((DATA_BITS * ARRAY_SIZE) * ARRAY_SIZE) - 1:0] results_flat;
	output wire ready;
	reg signed [(DATA_BITS * ARRAY_SIZE) - 1:0] a_reg;
	reg signed [(DATA_BITS * ARRAY_SIZE) - 1:0] b_reg;
	reg [ARRAY_SIZE - 1:0] en_row;
	reg [ARRAY_SIZE - 1:0] ce_row;
	reg [ARRAY_SIZE - 1:0] ca_row;
	reg [ARRAY_SIZE - 1:0] lw_row;
	integer i;
	always @(posedge clk)
		if (reset) begin
			a_reg <= 1'sb0;
			b_reg <= 1'sb0;
			en_row <= 1'sb0;
			ce_row <= 1'sb0;
			ca_row <= 1'sb0;
			lw_row <= 1'sb0;
		end
		else begin
			a_reg <= a_inputs_flat;
			b_reg <= b_inputs_flat;
			for (i = 0; i < ARRAY_SIZE; i = i + 1)
				begin
					en_row[i] <= enable;
					ce_row[i] <= compute_enable;
					ca_row[i] <= clear_acc;
					lw_row[i] <= load_weights;
				end
		end
	wire signed [DATA_BITS - 1:0] a_wire [ARRAY_SIZE - 1:0][ARRAY_SIZE:0];
	wire signed [DATA_BITS - 1:0] b_wire [ARRAY_SIZE:0][ARRAY_SIZE - 1:0];
	wire [DATA_BITS - 1:0] results [ARRAY_SIZE - 1:0][ARRAY_SIZE - 1:0];
	genvar _gv_row_1;
	genvar _gv_col_1;
	generate
		for (_gv_row_1 = 0; _gv_row_1 < ARRAY_SIZE; _gv_row_1 = _gv_row_1 + 1) begin : g_a_in
			localparam row = _gv_row_1;
			assign a_wire[row][0] = a_reg[((row + 1) * DATA_BITS) - 1-:DATA_BITS];
		end
		for (_gv_col_1 = 0; _gv_col_1 < ARRAY_SIZE; _gv_col_1 = _gv_col_1 + 1) begin : g_b_in
			localparam col = _gv_col_1;
			assign b_wire[0][col] = b_reg[((col + 1) * DATA_BITS) - 1-:DATA_BITS];
		end
		for (_gv_row_1 = 0; _gv_row_1 < ARRAY_SIZE; _gv_row_1 = _gv_row_1 + 1) begin : g_flat_r
			localparam row = _gv_row_1;
			for (_gv_col_1 = 0; _gv_col_1 < ARRAY_SIZE; _gv_col_1 = _gv_col_1 + 1) begin : g_flat_c
				localparam col = _gv_col_1;
				assign results_flat[((((row * ARRAY_SIZE) + col) + 1) * DATA_BITS) - 1-:DATA_BITS] = results[row][col];
			end
		end
		for (_gv_row_1 = 0; _gv_row_1 < ARRAY_SIZE; _gv_row_1 = _gv_row_1 + 1) begin : g_row
			localparam row = _gv_row_1;
			for (_gv_col_1 = 0; _gv_col_1 < ARRAY_SIZE; _gv_col_1 = _gv_col_1 + 1) begin : g_col
				localparam col = _gv_col_1;
				wire signed [DATA_BITS - 1:0] a_pe_out;
				wire signed [DATA_BITS - 1:0] b_pe_out;
				systolic_pe pe(
					.clk(clk),
					.reset(reset),
					.enable(en_row[row]),
					.clear_acc(ca_row[row]),
					.load_weight(lw_row[row]),
					.compute_enable(ce_row[row]),
					.a_in(a_wire[row][col]),
					.b_in(b_wire[row][col]),
					.a_out(a_pe_out),
					.b_out(b_pe_out),
					.acc_out(results[row][col])
				);
				if (((col + 1) < ARRAY_SIZE) && (((col + 1) % PIPE_INTERVAL) == 0)) begin : g_a_pipe
					reg signed [DATA_BITS - 1:0] a_preg;
					always @(posedge clk)
						if (reset)
							a_preg <= 1'sb0;
						else if (en_row[row])
							a_preg <= a_pe_out;
					assign a_wire[row][col + 1] = a_preg;
				end
				else begin : g_a_direct
					assign a_wire[row][col + 1] = a_pe_out;
				end
				if (((row + 1) < ARRAY_SIZE) && (((row + 1) % PIPE_INTERVAL) == 0)) begin : g_b_pipe
					reg signed [DATA_BITS - 1:0] b_preg;
					always @(posedge clk)
						if (reset)
							b_preg <= 1'sb0;
						else if (en_row[row])
							b_preg <= b_pe_out;
					assign b_wire[row + 1][col] = b_preg;
				end
				else begin : g_b_direct
					assign b_wire[row + 1][col] = b_pe_out;
				end
			end
		end
	endgenerate
	assign ready = ~ce_row[0];
endmodule