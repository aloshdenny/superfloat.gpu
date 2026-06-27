`default_nettype none
module activation (
	clk,
	reset,
	enable,
	core_state,
	activation_enable,
	activation_func,
	unbiased_activation,
	bias,
	activation_out
);
	parameter DATA_BITS = 16;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [2:0] core_state;
	input wire activation_enable;
	input wire [1:0] activation_func;
	input wire [DATA_BITS - 1:0] unbiased_activation;
	input wire [DATA_BITS - 1:0] bias;
	output wire [DATA_BITS - 1:0] activation_out;
	localparam [DATA_BITS - 1:0] Q115_ZERO = 16'h0000;
	localparam [DATA_BITS - 1:0] Q115_MAX = 16'h7fff;
	localparam [DATA_BITS - 1:0] Q115_MIN = 16'hffff;
	localparam [DATA_BITS - 1:0] Q115_LEAKY_ALPHA = 16'h0148;
	localparam [1:0] ACT_NONE = 2'b00;
	localparam [1:0] ACT_RELU = 2'b01;
	localparam [1:0] ACT_LEAKY_RELU = 2'b10;
	localparam [1:0] ACT_CLIPPED_RELU = 2'b11;
	reg [DATA_BITS - 1:0] activation_out_reg;
	assign activation_out = activation_out_reg;
	wire signed [15:0] act_signed = (unbiased_activation[15] ? -$signed({1'b0, unbiased_activation[14:0]}) : $signed({1'b0, unbiased_activation[14:0]}));
	wire signed [15:0] bias_signed = (bias[15] ? -$signed({1'b0, bias[14:0]}) : $signed({1'b0, bias[14:0]}));
	wire signed [16:0] biased_sum_ext = {act_signed[15], act_signed} + {bias_signed[15], bias_signed};
	wire signed [15:0] biased_sum_sat = (biased_sum_ext > 32767 ? 16'sd32767 : (biased_sum_ext < -32767 ? -16'sd32767 : biased_sum_ext[15:0]));
	wire [15:0] abs_biased_sum_sat = -biased_sum_sat;
	wire [DATA_BITS - 1:0] biased_sm = (biased_sum_sat < 0 ? {1'b1, abs_biased_sum_sat[14:0]} : {1'b0, biased_sum_sat[14:0]});
	wire [DATA_BITS - 1:0] biased_activation = (biased_sm == 16'h8000 ? 16'h0000 : biased_sm);
	wire is_negative = biased_activation[15];
	wire [14:0] leaky_mantissa = biased_activation[14:0] >> 7;
	wire [DATA_BITS - 1:0] leaky_value = (leaky_mantissa == 15'b000000000000000 ? Q115_ZERO : {1'b1, leaky_mantissa});
	reg [DATA_BITS - 1:0] activated_value;
	always @(*)
		case (activation_func)
			ACT_NONE: activated_value = biased_activation;
			ACT_RELU: activated_value = (is_negative ? Q115_ZERO : biased_activation);
			ACT_LEAKY_RELU: activated_value = (is_negative ? leaky_value : biased_activation);
			ACT_CLIPPED_RELU: activated_value = (is_negative ? Q115_ZERO : biased_activation);
			default: activated_value = biased_activation;
		endcase
	always @(posedge clk)
		if (reset)
			activation_out_reg <= {DATA_BITS {1'b0}};
		else if (enable) begin
			if ((core_state == 3'b101) && activation_enable)
				activation_out_reg <= activated_value;
		end
endmodule
`default_nettype none
module alu (
	clk,
	reset,
	enable,
	core_state,
	decoded_alu_arithmetic_mux,
	decoded_alu_output_mux,
	rs,
	rt,
	alu_out
);
	parameter DATA_BITS = 16;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [2:0] core_state;
	input wire [1:0] decoded_alu_arithmetic_mux;
	input wire decoded_alu_output_mux;
	input wire [DATA_BITS - 1:0] rs;
	input wire [DATA_BITS - 1:0] rt;
	output wire [DATA_BITS - 1:0] alu_out;
	localparam ADD = 2'b00;
	localparam SUB = 2'b01;
	localparam MUL = 2'b10;
	localparam DIV = 2'b11;
	reg [DATA_BITS - 1:0] alu_out_reg;
	assign alu_out = alu_out_reg;
	always @(posedge clk)
		if (reset)
			alu_out_reg <= {DATA_BITS {1'b0}};
		else if (enable) begin
			if (core_state == 3'b101) begin
				if (decoded_alu_output_mux == 1)
					alu_out_reg <= {{DATA_BITS - 3 {1'b0}}, $signed(rs) < $signed(rt), rs == rt, $signed(rs) > $signed(rt)};
				else
					case (decoded_alu_arithmetic_mux)
						ADD: alu_out_reg <= rs + rt;
						SUB: alu_out_reg <= rs - rt;
						MUL: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, rs[7:0] * rt[7:0]};
						DIV:
							case (rt[7:0])
								8'd1: alu_out_reg <= rs;
								8'd2: alu_out_reg <= rs >> 1;
								8'd3: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, rs[7:0] / 8'd3};
								8'd4: alu_out_reg <= rs >> 2;
								8'd8: alu_out_reg <= rs >> 3;
								8'd9: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, rs[7:0] / 8'd9};
								8'd10: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, rs[7:0] / 8'd10};
								8'd11: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, rs[7:0] / 8'd11};
								8'd12: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, rs[7:0] / 8'd12};
								8'd16: alu_out_reg <= rs >> 4;
								8'd32: alu_out_reg <= rs >> 5;
								8'd64: alu_out_reg <= rs >> 6;
								default: alu_out_reg <= {DATA_BITS {1'b0}};
							endcase
					endcase
			end
		end
endmodule
`default_nettype none
module branch_diverge (
	clk,
	reset,
	enable,
	branch_instruction,
	branch_taken,
	branch_target,
	fallthrough_pc,
	reconverge_pc,
	current_pc,
	active_mask,
	next_pc,
	diverged,
	stall
);
	parameter THREADS_PER_WARP = 8;
	parameter STACK_DEPTH = 8;
	parameter PC_BITS = 8;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire branch_instruction;
	input wire [THREADS_PER_WARP - 1:0] branch_taken;
	input wire [PC_BITS - 1:0] branch_target;
	input wire [PC_BITS - 1:0] fallthrough_pc;
	input wire [PC_BITS - 1:0] reconverge_pc;
	input wire [PC_BITS - 1:0] current_pc;
	output reg [THREADS_PER_WARP - 1:0] active_mask;
	output reg [PC_BITS - 1:0] next_pc;
	output reg diverged;
	output reg stall;
	reg [THREADS_PER_WARP - 1:0] stack_mask [0:STACK_DEPTH - 1];
	reg [PC_BITS - 1:0] stack_reconverge [0:STACK_DEPTH - 1];
	reg [PC_BITS - 1:0] stack_target_pc [0:STACK_DEPTH - 1];
	reg [STACK_DEPTH - 1:0] stack_valid;
	reg [$clog2(STACK_DEPTH + 1) - 1:0] stack_ptr;
	reg [THREADS_PER_WARP - 1:0] full_mask;
	localparam IDX_BITS = $clog2(STACK_DEPTH);
	wire [$clog2(STACK_DEPTH + 1) - 1:0] prev_ptr = (stack_ptr > 0 ? stack_ptr - 1 : 0);
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [IDX_BITS - 1:0] sv2v_cast_73482;
		input reg [IDX_BITS - 1:0] inp;
		sv2v_cast_73482 = inp;
	endfunction
	wire at_reconverge = ((sv2v_cast_32(stack_ptr) > 0) && stack_valid[sv2v_cast_73482(prev_ptr)]) && (current_pc == stack_reconverge[sv2v_cast_73482(prev_ptr)]);
	integer i;
	reg [$clog2(THREADS_PER_WARP):0] taken_count;
	reg [$clog2(THREADS_PER_WARP):0] not_taken_count;
	always @(*) begin
		taken_count = 0;
		not_taken_count = 0;
		for (i = 0; i < THREADS_PER_WARP; i = i + 1)
			if (active_mask[i]) begin
				if (branch_taken[i])
					taken_count = taken_count + 1;
				else
					not_taken_count = not_taken_count + 1;
			end
	end
	wire will_diverge = (branch_instruction && (taken_count > 0)) && (not_taken_count > 0);
	wire all_take = branch_instruction && (not_taken_count == 0);
	integer j;
	always @(posedge clk)
		if (reset) begin
			active_mask <= {THREADS_PER_WARP {1'b1}};
			full_mask <= {THREADS_PER_WARP {1'b1}};
			stack_ptr <= 0;
			stack_valid <= {STACK_DEPTH {1'b0}};
			diverged <= 1'b0;
			stall <= 1'b0;
			next_pc <= {PC_BITS {1'b0}};
			for (j = 0; j < STACK_DEPTH; j = j + 1)
				begin
					stack_mask[j] <= {THREADS_PER_WARP {1'b0}};
					stack_reconverge[j] <= {PC_BITS {1'b0}};
					stack_target_pc[j] <= {PC_BITS {1'b0}};
				end
		end
		else if (enable) begin
			stall <= 1'b0;
			if (at_reconverge && (stack_ptr > 0)) begin
				stack_ptr <= stack_ptr - 1;
				if (stack_mask[sv2v_cast_73482(prev_ptr)] != {THREADS_PER_WARP {1'b0}}) begin
					active_mask <= stack_mask[sv2v_cast_73482(prev_ptr)];
					next_pc <= stack_target_pc[sv2v_cast_73482(prev_ptr)];
					stack_mask[sv2v_cast_73482(prev_ptr)] <= {THREADS_PER_WARP {1'b0}};
					stall <= 1'b1;
				end
				else begin
					active_mask <= full_mask;
					diverged <= stack_ptr > 1;
				end
			end
			else if (branch_instruction) begin
				if (will_diverge) begin
					if (sv2v_cast_32(stack_ptr) < STACK_DEPTH) begin
						stack_mask[sv2v_cast_73482(stack_ptr)] <= active_mask & ~branch_taken;
						stack_reconverge[sv2v_cast_73482(stack_ptr)] <= reconverge_pc;
						stack_target_pc[sv2v_cast_73482(stack_ptr)] <= fallthrough_pc;
						stack_valid[sv2v_cast_73482(stack_ptr)] <= 1'b1;
						stack_ptr <= stack_ptr + 1;
						active_mask <= active_mask & branch_taken;
						next_pc <= branch_target;
						diverged <= 1'b1;
						stall <= 1'b1;
					end
				end
				else if (all_take)
					next_pc <= branch_target;
				else
					next_pc <= fallthrough_pc;
			end
		end
endmodule
`default_nettype none
module cache (
	clk,
	reset,
	read_valid,
	read_address,
	read_ready,
	read_data,
	mem_read_valid,
	mem_read_address,
	mem_read_ready,
	mem_read_data
);
	parameter ADDR_BITS = 8;
	parameter DATA_BITS = 16;
	parameter CACHE_SIZE = 16;
	input wire clk;
	input wire reset;
	input wire read_valid;
	input wire [ADDR_BITS - 1:0] read_address;
	output reg read_ready;
	output reg [DATA_BITS - 1:0] read_data;
	output reg mem_read_valid;
	output reg [ADDR_BITS - 1:0] mem_read_address;
	input wire mem_read_ready;
	input wire [DATA_BITS - 1:0] mem_read_data;
	localparam INDEX_BITS = $clog2(CACHE_SIZE);
	localparam TAG_BITS = ADDR_BITS - INDEX_BITS;
	localparam IDLE = 2'b00;
	localparam CHECK = 2'b01;
	localparam FETCH = 2'b10;
	localparam UPDATE = 2'b11;
	reg [1:0] cache_state;
	reg [DATA_BITS - 1:0] cache_data [CACHE_SIZE - 1:0];
	reg [TAG_BITS - 1:0] cache_tag [CACHE_SIZE - 1:0];
	reg cache_valid [CACHE_SIZE - 1:0];
	wire [INDEX_BITS - 1:0] addr_index = read_address[INDEX_BITS - 1:0];
	wire [TAG_BITS - 1:0] addr_tag = read_address[ADDR_BITS - 1:INDEX_BITS];
	wire tag_match = cache_tag[addr_index] == addr_tag;
	wire cache_hit = cache_valid[addr_index] && tag_match;
	reg [ADDR_BITS - 1:0] pending_address;
	reg [INDEX_BITS - 1:0] pending_index;
	reg [TAG_BITS - 1:0] pending_tag;
	integer i;
	always @(posedge clk)
		if (reset) begin
			cache_state <= IDLE;
			read_ready <= 1'b0;
			read_data <= {DATA_BITS {1'b0}};
			mem_read_valid <= 1'b0;
			mem_read_address <= {ADDR_BITS {1'b0}};
			pending_address <= {ADDR_BITS {1'b0}};
			pending_index <= {INDEX_BITS {1'b0}};
			pending_tag <= {TAG_BITS {1'b0}};
			for (i = 0; i < CACHE_SIZE; i = i + 1)
				begin
					cache_valid[i] <= 1'b0;
					cache_tag[i] <= {TAG_BITS {1'b0}};
					cache_data[i] <= {DATA_BITS {1'b0}};
				end
		end
		else
			case (cache_state)
				IDLE: begin
					read_ready <= 1'b0;
					mem_read_valid <= 1'b0;
					if (read_valid) begin
						cache_state <= CHECK;
						pending_address <= read_address;
						pending_index <= addr_index;
						pending_tag <= addr_tag;
					end
				end
				CHECK:
					if (cache_hit) begin
						read_data <= cache_data[pending_index];
						read_ready <= 1'b1;
						cache_state <= IDLE;
					end
					else begin
						mem_read_valid <= 1'b1;
						mem_read_address <= pending_address;
						cache_state <= FETCH;
					end
				FETCH:
					if (mem_read_ready) begin
						mem_read_valid <= 1'b0;
						cache_state <= UPDATE;
					end
				UPDATE: begin
					cache_data[pending_index] <= mem_read_data;
					cache_tag[pending_index] <= pending_tag;
					cache_valid[pending_index] <= 1'b1;
					read_data <= mem_read_data;
					read_ready <= 1'b1;
					cache_state <= IDLE;
				end
				default: cache_state <= IDLE;
			endcase
endmodule
`default_nettype none
module controller (
	clk,
	reset,
	consumer_read_valid,
	consumer_read_address_flat,
	consumer_read_ready,
	consumer_read_data_flat,
	consumer_write_valid,
	consumer_write_address_flat,
	consumer_write_data_flat,
	consumer_write_ready,
	mem_read_valid,
	mem_read_address_flat,
	mem_read_ready,
	mem_read_data_flat,
	mem_write_valid,
	mem_write_address_flat,
	mem_write_data_flat,
	mem_write_ready
);
	parameter ADDR_BITS = 8;
	parameter DATA_BITS = 16;
	parameter NUM_CONSUMERS = 4;
	parameter NUM_CHANNELS = 1;
	parameter WRITE_ENABLE = 1;
	input wire clk;
	input wire reset;
	input wire [NUM_CONSUMERS - 1:0] consumer_read_valid;
	input wire [(ADDR_BITS * NUM_CONSUMERS) - 1:0] consumer_read_address_flat;
	output reg [NUM_CONSUMERS - 1:0] consumer_read_ready;
	output wire [(DATA_BITS * NUM_CONSUMERS) - 1:0] consumer_read_data_flat;
	input wire [NUM_CONSUMERS - 1:0] consumer_write_valid;
	input wire [(ADDR_BITS * NUM_CONSUMERS) - 1:0] consumer_write_address_flat;
	input wire [(DATA_BITS * NUM_CONSUMERS) - 1:0] consumer_write_data_flat;
	output reg [NUM_CONSUMERS - 1:0] consumer_write_ready;
	output reg [NUM_CHANNELS - 1:0] mem_read_valid;
	output wire [(ADDR_BITS * NUM_CHANNELS) - 1:0] mem_read_address_flat;
	input wire [NUM_CHANNELS - 1:0] mem_read_ready;
	input wire [(DATA_BITS * NUM_CHANNELS) - 1:0] mem_read_data_flat;
	output reg [NUM_CHANNELS - 1:0] mem_write_valid;
	output wire [(ADDR_BITS * NUM_CHANNELS) - 1:0] mem_write_address_flat;
	output wire [(DATA_BITS * NUM_CHANNELS) - 1:0] mem_write_data_flat;
	input wire [NUM_CHANNELS - 1:0] mem_write_ready;
	wire [ADDR_BITS - 1:0] consumer_read_address [NUM_CONSUMERS - 1:0];
	reg [DATA_BITS - 1:0] consumer_read_data [NUM_CONSUMERS - 1:0];
	wire [ADDR_BITS - 1:0] consumer_write_address [NUM_CONSUMERS - 1:0];
	wire [DATA_BITS - 1:0] consumer_write_data [NUM_CONSUMERS - 1:0];
	reg [ADDR_BITS - 1:0] mem_read_address [NUM_CHANNELS - 1:0];
	wire [DATA_BITS - 1:0] mem_read_data [NUM_CHANNELS - 1:0];
	reg [ADDR_BITS - 1:0] mem_write_address [NUM_CHANNELS - 1:0];
	reg [DATA_BITS - 1:0] mem_write_data [NUM_CHANNELS - 1:0];
	genvar _gv_c_1;
	generate
		for (_gv_c_1 = 0; _gv_c_1 < NUM_CONSUMERS; _gv_c_1 = _gv_c_1 + 1) begin : unflatten_consumer
			localparam c = _gv_c_1;
			assign consumer_read_address[c] = consumer_read_address_flat[((c + 1) * ADDR_BITS) - 1:c * ADDR_BITS];
			assign consumer_write_address[c] = consumer_write_address_flat[((c + 1) * ADDR_BITS) - 1:c * ADDR_BITS];
			assign consumer_write_data[c] = consumer_write_data_flat[((c + 1) * DATA_BITS) - 1:c * DATA_BITS];
		end
	endgenerate
	genvar _gv_m_1;
	generate
		for (_gv_m_1 = 0; _gv_m_1 < NUM_CHANNELS; _gv_m_1 = _gv_m_1 + 1) begin : unflatten_mem
			localparam m = _gv_m_1;
			assign mem_read_data[m] = mem_read_data_flat[((m + 1) * DATA_BITS) - 1:m * DATA_BITS];
		end
	endgenerate
	genvar _gv_f_1;
	generate
		for (_gv_f_1 = 0; _gv_f_1 < NUM_CONSUMERS; _gv_f_1 = _gv_f_1 + 1) begin : flatten_consumer_outputs
			localparam f = _gv_f_1;
			assign consumer_read_data_flat[((f + 1) * DATA_BITS) - 1:f * DATA_BITS] = consumer_read_data[f];
		end
		for (_gv_f_1 = 0; _gv_f_1 < NUM_CHANNELS; _gv_f_1 = _gv_f_1 + 1) begin : flatten_mem_outputs
			localparam f = _gv_f_1;
			assign mem_read_address_flat[((f + 1) * ADDR_BITS) - 1:f * ADDR_BITS] = mem_read_address[f];
			assign mem_write_address_flat[((f + 1) * ADDR_BITS) - 1:f * ADDR_BITS] = mem_write_address[f];
			assign mem_write_data_flat[((f + 1) * DATA_BITS) - 1:f * DATA_BITS] = mem_write_data[f];
		end
	endgenerate
	localparam IDLE = 3'b000;
	localparam READ_WAITING = 3'b010;
	localparam WRITE_WAITING = 3'b011;
	localparam READ_RELAYING = 3'b100;
	localparam WRITE_RELAYING = 3'b101;
	localparam SEL_WIDTH = ($clog2(NUM_CONSUMERS) > 0 ? $clog2(NUM_CONSUMERS) : 1);
	reg [2:0] controller_state [NUM_CHANNELS - 1:0];
	reg [SEL_WIDTH - 1:0] current_consumer [NUM_CHANNELS - 1:0];
	reg [NUM_CONSUMERS - 1:0] channel_serving_consumer;
	reg [NUM_CONSUMERS - 1:0] serving_next;
	integer sel;
	reg sel_is_write;
	integer i;
	integer j;
	integer k;
	function automatic signed [SEL_WIDTH - 1:0] sv2v_cast_61068_signed;
		input reg signed [SEL_WIDTH - 1:0] inp;
		sv2v_cast_61068_signed = inp;
	endfunction
	always @(posedge clk)
		if (reset) begin
			mem_read_valid <= {NUM_CHANNELS {1'b0}};
			mem_write_valid <= {NUM_CHANNELS {1'b0}};
			consumer_read_ready <= {NUM_CONSUMERS {1'b0}};
			consumer_write_ready <= {NUM_CONSUMERS {1'b0}};
			channel_serving_consumer <= 0;
			serving_next = {NUM_CONSUMERS {1'b0}};
			for (k = 0; k < NUM_CHANNELS; k = k + 1)
				begin
					mem_read_address[k] <= {ADDR_BITS {1'b0}};
					mem_write_address[k] <= {ADDR_BITS {1'b0}};
					mem_write_data[k] <= {DATA_BITS {1'b0}};
				end
			for (k = 0; k < NUM_CONSUMERS; k = k + 1)
				consumer_read_data[k] <= {DATA_BITS {1'b0}};
			for (k = 0; k < NUM_CHANNELS; k = k + 1)
				begin
					controller_state[k] <= IDLE;
					current_consumer[k] <= {SEL_WIDTH {1'b0}};
				end
		end
		else begin
			serving_next = channel_serving_consumer;
			for (i = 0; i < NUM_CHANNELS; i = i + 1)
				case (controller_state[i])
					IDLE: begin
						sel = -1;
						sel_is_write = 1'b0;
						for (j = 0; j < NUM_CONSUMERS; j = j + 1)
							if (sel == -1) begin
								if (consumer_read_valid[j] && !serving_next[j]) begin
									sel = j;
									sel_is_write = 1'b0;
								end
								else if ((WRITE_ENABLE && consumer_write_valid[j]) && !serving_next[j]) begin
									sel = j;
									sel_is_write = 1'b1;
								end
							end
						if (sel != -1) begin
							serving_next[sel] = 1'b1;
							current_consumer[i] <= sv2v_cast_61068_signed(sel);
							if (!sel_is_write) begin
								mem_read_valid[i] <= 1'b1;
								mem_read_address[i] <= consumer_read_address[sel];
								controller_state[i] <= READ_WAITING;
							end
							else begin
								mem_write_valid[i] <= 1'b1;
								mem_write_address[i] <= consumer_write_address[sel];
								mem_write_data[i] <= consumer_write_data[sel];
								controller_state[i] <= WRITE_WAITING;
							end
						end
					end
					READ_WAITING:
						if (mem_read_ready[i]) begin
							mem_read_valid[i] <= 0;
							consumer_read_ready[current_consumer[i]] <= 1;
							consumer_read_data[current_consumer[i]] <= mem_read_data[i];
							controller_state[i] <= READ_RELAYING;
						end
					WRITE_WAITING:
						if (mem_write_ready[i]) begin
							mem_write_valid[i] <= 0;
							consumer_write_ready[current_consumer[i]] <= 1;
							controller_state[i] <= WRITE_RELAYING;
						end
					READ_RELAYING:
						if (!consumer_read_valid[current_consumer[i]]) begin
							serving_next[current_consumer[i]] = 1'b0;
							consumer_read_ready[current_consumer[i]] <= 0;
							controller_state[i] <= IDLE;
						end
					WRITE_RELAYING:
						if (!consumer_write_valid[current_consumer[i]]) begin
							serving_next[current_consumer[i]] = 1'b0;
							consumer_write_ready[current_consumer[i]] <= 0;
							controller_state[i] <= IDLE;
						end
					default: controller_state[i] <= IDLE;
				endcase
			channel_serving_consumer <= serving_next;
			channel_serving_consumer <= serving_next;
		end
endmodule
`default_nettype none
module core (
	clk,
	reset,
	start,
	done,
	block_id,
	thread_count,
	core_state_for_decode,
	instruction_for_decode,
	decoded_rd_address,
	decoded_rs_address,
	decoded_rt_address,
	decoded_nzp,
	decoded_immediate,
	decoded_reg_write_enable,
	decoded_mem_read_enable,
	decoded_mem_write_enable,
	decoded_nzp_write_enable,
	decoded_reg_input_mux,
	decoded_alu_arithmetic_mux,
	decoded_alu_output_mux,
	decoded_pc_mux,
	decoded_fma_enable,
	decoded_act_enable,
	decoded_act_func,
	decoded_systolic_enable,
	decoded_systolic_op,
	decoded_systolic_idx,
	decoded_branch,
	decoded_ret,
	program_mem_read_valid,
	program_mem_read_address,
	program_mem_read_ready,
	program_mem_read_data,
	data_mem_read_valid,
	data_mem_read_address_flat,
	data_mem_read_ready,
	data_mem_read_data_flat,
	data_mem_write_valid,
	data_mem_write_address_flat,
	data_mem_write_data_flat,
	data_mem_write_ready
);
	parameter DATA_MEM_ADDR_BITS = 19;
	parameter DATA_MEM_DATA_BITS = 16;
	parameter PROGRAM_MEM_ADDR_BITS = 9;
	parameter PROGRAM_MEM_DATA_BITS = 16;
	parameter THREADS_PER_BLOCK = 4;
	parameter SYSTOLIC_SIZE = 2;
	parameter NUM_SYSTOLIC_ARRAYS = 2;
	parameter CACHE_SIZE = 4;
	input wire clk;
	input wire reset;
	input wire start;
	output wire done;
	input wire [7:0] block_id;
	input wire [$clog2(THREADS_PER_BLOCK):0] thread_count;
	output wire [2:0] core_state_for_decode;
	output wire [15:0] instruction_for_decode;
	input wire [3:0] decoded_rd_address;
	input wire [3:0] decoded_rs_address;
	input wire [3:0] decoded_rt_address;
	input wire [2:0] decoded_nzp;
	input wire [7:0] decoded_immediate;
	input wire decoded_reg_write_enable;
	input wire decoded_mem_read_enable;
	input wire decoded_mem_write_enable;
	input wire decoded_nzp_write_enable;
	input wire [2:0] decoded_reg_input_mux;
	input wire [1:0] decoded_alu_arithmetic_mux;
	input wire decoded_alu_output_mux;
	input wire decoded_pc_mux;
	input wire decoded_fma_enable;
	input wire decoded_act_enable;
	input wire [1:0] decoded_act_func;
	input wire decoded_systolic_enable;
	input wire [1:0] decoded_systolic_op;
	input wire decoded_systolic_idx;
	input wire decoded_branch;
	input wire decoded_ret;
	output wire program_mem_read_valid;
	output wire [PROGRAM_MEM_ADDR_BITS - 1:0] program_mem_read_address;
	input wire program_mem_read_ready;
	input wire [PROGRAM_MEM_DATA_BITS - 1:0] program_mem_read_data;
	output wire [THREADS_PER_BLOCK - 1:0] data_mem_read_valid;
	output wire [(DATA_MEM_ADDR_BITS * THREADS_PER_BLOCK) - 1:0] data_mem_read_address_flat;
	input wire [THREADS_PER_BLOCK - 1:0] data_mem_read_ready;
	input wire [(DATA_MEM_DATA_BITS * THREADS_PER_BLOCK) - 1:0] data_mem_read_data_flat;
	output wire [THREADS_PER_BLOCK - 1:0] data_mem_write_valid;
	output wire [(DATA_MEM_ADDR_BITS * THREADS_PER_BLOCK) - 1:0] data_mem_write_address_flat;
	output wire [(DATA_MEM_DATA_BITS * THREADS_PER_BLOCK) - 1:0] data_mem_write_data_flat;
	input wire [THREADS_PER_BLOCK - 1:0] data_mem_write_ready;
	wire [DATA_MEM_ADDR_BITS - 1:0] data_mem_read_address [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] data_mem_read_data [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_ADDR_BITS - 1:0] data_mem_write_address [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] data_mem_write_data [THREADS_PER_BLOCK - 1:0];
	genvar _gv_flat_idx_1;
	generate
		for (_gv_flat_idx_1 = 0; _gv_flat_idx_1 < THREADS_PER_BLOCK; _gv_flat_idx_1 = _gv_flat_idx_1 + 1) begin : unflatten_mem
			localparam flat_idx = _gv_flat_idx_1;
			assign data_mem_read_data[flat_idx] = data_mem_read_data_flat[((flat_idx + 1) * DATA_MEM_DATA_BITS) - 1:flat_idx * DATA_MEM_DATA_BITS];
		end
	endgenerate
	genvar _gv_out_idx_1;
	generate
		for (_gv_out_idx_1 = 0; _gv_out_idx_1 < THREADS_PER_BLOCK; _gv_out_idx_1 = _gv_out_idx_1 + 1) begin : flatten_out
			localparam out_idx = _gv_out_idx_1;
			assign data_mem_read_address_flat[((out_idx + 1) * DATA_MEM_ADDR_BITS) - 1:out_idx * DATA_MEM_ADDR_BITS] = data_mem_read_address[out_idx];
			assign data_mem_write_address_flat[((out_idx + 1) * DATA_MEM_ADDR_BITS) - 1:out_idx * DATA_MEM_ADDR_BITS] = data_mem_write_address[out_idx];
			assign data_mem_write_data_flat[((out_idx + 1) * DATA_MEM_DATA_BITS) - 1:out_idx * DATA_MEM_DATA_BITS] = data_mem_write_data[out_idx];
		end
	endgenerate
	reg [2:0] core_state;
	reg [2:0] fetcher_state;
	reg [15:0] instruction;
	assign core_state_for_decode = core_state;
	assign instruction_for_decode = instruction;
	reg [PROGRAM_MEM_ADDR_BITS - 1:0] current_pc;
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] next_pc [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] rs [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] rt [THREADS_PER_BLOCK - 1:0];
	wire [1:0] lsu_state [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] lsu_out [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] alu_out [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] fma_out [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] act_out [THREADS_PER_BLOCK - 1:0];
	reg [DATA_MEM_DATA_BITS - 1:0] systolic_out [THREADS_PER_BLOCK - 1:0];
	reg [(2 * THREADS_PER_BLOCK) - 1:0] lsu_state_flat;
	reg [(PROGRAM_MEM_ADDR_BITS * THREADS_PER_BLOCK) - 1:0] next_pc_flat;
	integer lsu_idx;
	always @(*)
		for (lsu_idx = 0; lsu_idx < THREADS_PER_BLOCK; lsu_idx = lsu_idx + 1)
			begin
				lsu_state_flat[lsu_idx * 2+:2] = lsu_state[lsu_idx];
				next_pc_flat[lsu_idx * PROGRAM_MEM_ADDR_BITS+:PROGRAM_MEM_ADDR_BITS] = next_pc[lsu_idx];
			end
	wire [DATA_MEM_DATA_BITS - 1:0] rd_data [THREADS_PER_BLOCK - 1:0];
	wire [3:1] sv2v_tmp_fetcher_instance_fetcher_state;
	always @(*) fetcher_state = sv2v_tmp_fetcher_instance_fetcher_state;
	wire [16:1] sv2v_tmp_fetcher_instance_instruction;
	always @(*) instruction = sv2v_tmp_fetcher_instance_instruction;
	fetcher #(
		.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
		.PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS)
	) fetcher_instance(
		.clk(clk),
		.reset(reset),
		.core_state(core_state),
		.current_pc(current_pc),
		.mem_read_valid(program_mem_read_valid),
		.mem_read_address(program_mem_read_address),
		.mem_read_ready(program_mem_read_ready),
		.mem_read_data(program_mem_read_data),
		.fetcher_state(sv2v_tmp_fetcher_instance_fetcher_state),
		.instruction(sv2v_tmp_fetcher_instance_instruction)
	);
	reg [3:0] pipe_rd_address;
	reg [3:0] pipe_rs_address;
	reg [3:0] pipe_rt_address;
	reg [2:0] pipe_nzp;
	reg [7:0] pipe_immediate;
	reg pipe_reg_write_enable;
	reg pipe_mem_read_enable;
	reg pipe_mem_write_enable;
	reg pipe_nzp_write_enable;
	reg [2:0] pipe_reg_input_mux;
	reg [1:0] pipe_alu_arithmetic_mux;
	reg pipe_alu_output_mux;
	reg pipe_pc_mux;
	reg pipe_fma_enable;
	reg pipe_act_enable;
	reg [1:0] pipe_act_func;
	reg pipe_systolic_enable;
	reg [1:0] pipe_systolic_op;
	reg pipe_systolic_idx;
	reg pipe_ret;
	reg pipe_branch;
	always @(posedge clk)
		if (reset) begin
			pipe_rd_address <= 4'b0000;
			pipe_rs_address <= 4'b0000;
			pipe_rt_address <= 4'b0000;
			pipe_nzp <= 3'b000;
			pipe_immediate <= 8'b00000000;
			pipe_reg_write_enable <= 1'b0;
			pipe_mem_read_enable <= 1'b0;
			pipe_mem_write_enable <= 1'b0;
			pipe_nzp_write_enable <= 1'b0;
			pipe_reg_input_mux <= 3'b000;
			pipe_alu_arithmetic_mux <= 2'b00;
			pipe_alu_output_mux <= 1'b0;
			pipe_pc_mux <= 1'b0;
			pipe_fma_enable <= 1'b0;
			pipe_act_enable <= 1'b0;
			pipe_act_func <= 2'b00;
			pipe_systolic_enable <= 1'b0;
			pipe_systolic_op <= 2'b00;
			pipe_systolic_idx <= 1'b0;
			pipe_ret <= 1'b0;
			pipe_branch <= 1'b0;
		end
		else begin
			pipe_rd_address <= decoded_rd_address;
			pipe_rs_address <= decoded_rs_address;
			pipe_rt_address <= decoded_rt_address;
			pipe_nzp <= decoded_nzp;
			pipe_immediate <= decoded_immediate;
			pipe_reg_write_enable <= decoded_reg_write_enable;
			pipe_mem_read_enable <= decoded_mem_read_enable;
			pipe_mem_write_enable <= decoded_mem_write_enable;
			pipe_nzp_write_enable <= decoded_nzp_write_enable;
			pipe_reg_input_mux <= decoded_reg_input_mux;
			pipe_alu_arithmetic_mux <= decoded_alu_arithmetic_mux;
			pipe_alu_output_mux <= decoded_alu_output_mux;
			pipe_pc_mux <= decoded_pc_mux;
			pipe_fma_enable <= decoded_fma_enable;
			pipe_act_enable <= decoded_act_enable;
			pipe_act_func <= decoded_act_func;
			pipe_systolic_enable <= decoded_systolic_enable;
			pipe_systolic_op <= decoded_systolic_op;
			pipe_systolic_idx <= decoded_systolic_idx;
			pipe_ret <= decoded_ret;
			pipe_branch <= decoded_branch;
		end
	wire [THREADS_PER_BLOCK - 1:0] branch_taken;
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] branch_target;
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] reconverge_pc;
	wire [THREADS_PER_BLOCK - 1:0] active_mask;
	wire diverged;
	wire per_thread_branch_taken [THREADS_PER_BLOCK - 1:0];
	integer br_idx;
	reg [THREADS_PER_BLOCK - 1:0] branch_taken_reg;
	always @(*)
		for (br_idx = 0; br_idx < THREADS_PER_BLOCK; br_idx = br_idx + 1)
			branch_taken_reg[br_idx] = per_thread_branch_taken[br_idx];
	assign branch_taken = branch_taken_reg;
	assign branch_target = {{PROGRAM_MEM_ADDR_BITS - 8 {1'b0}}, pipe_immediate};
	assign reconverge_pc = current_pc + 2;
	wire [3:1] sv2v_tmp_scheduler_instance_core_state;
	always @(*) core_state = sv2v_tmp_scheduler_instance_core_state;
	wire [PROGRAM_MEM_ADDR_BITS:1] sv2v_tmp_scheduler_instance_current_pc;
	always @(*) current_pc = sv2v_tmp_scheduler_instance_current_pc;
	scheduler #(
		.THREADS_PER_BLOCK(THREADS_PER_BLOCK),
		.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
	) scheduler_instance(
		.clk(clk),
		.reset(reset),
		.start(start),
		.fetcher_state(fetcher_state),
		.core_state(sv2v_tmp_scheduler_instance_core_state),
		.decoded_fma_enable(pipe_fma_enable),
		.decoded_ret(pipe_ret),
		.decoded_branch(pipe_branch),
		.branch_taken(branch_taken),
		.branch_target(branch_target),
		.reconverge_pc(reconverge_pc),
		.lsu_state_flat(lsu_state_flat),
		.current_pc(sv2v_tmp_scheduler_instance_current_pc),
		.next_pc_flat(next_pc_flat),
		.active_mask(active_mask),
		.diverged(diverged),
		.done(done)
	);
	reg [DATA_MEM_DATA_BITS - 1:0] pipe_rs [THREADS_PER_BLOCK - 1:0];
	reg [DATA_MEM_DATA_BITS - 1:0] pipe_rt [THREADS_PER_BLOCK - 1:0];
	reg [DATA_MEM_DATA_BITS - 1:0] pipe_rd_data [THREADS_PER_BLOCK - 1:0];
	always @(posedge clk)
		if (reset) begin : sv2v_autoblock_1
			integer t;
			for (t = 0; t < THREADS_PER_BLOCK; t = t + 1)
				begin
					pipe_rs[t] <= {DATA_MEM_DATA_BITS {1'b0}};
					pipe_rt[t] <= {DATA_MEM_DATA_BITS {1'b0}};
					pipe_rd_data[t] <= {DATA_MEM_DATA_BITS {1'b0}};
				end
		end
		else if (core_state == 3'b010) begin : sv2v_autoblock_2
			integer t;
			for (t = 0; t < THREADS_PER_BLOCK; t = t + 1)
				begin
					pipe_rs[t] <= rs[t];
					pipe_rt[t] <= rt[t];
					pipe_rd_data[t] <= rd_data[t];
				end
		end
	genvar _gv_i_1;
	generate
		for (_gv_i_1 = 0; _gv_i_1 < THREADS_PER_BLOCK; _gv_i_1 = _gv_i_1 + 1) begin : threads
			localparam i = _gv_i_1;
			alu #(.DATA_BITS(DATA_MEM_DATA_BITS)) alu_instance(
				.clk(clk),
				.reset(reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.decoded_alu_arithmetic_mux(pipe_alu_arithmetic_mux),
				.decoded_alu_output_mux(pipe_alu_output_mux),
				.rs(pipe_rs[i]),
				.rt(pipe_rt[i]),
				.alu_out(alu_out[i])
			);
			fma #(.DATA_BITS(DATA_MEM_DATA_BITS)) fma_instance(
				.clk(clk),
				.reset(reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.decoded_fma_enable(pipe_fma_enable),
				.rs(pipe_rs[i]),
				.rt(pipe_rt[i]),
				.rq(pipe_rd_data[i]),
				.fma_out(fma_out[i])
			);
			activation #(.DATA_BITS(DATA_MEM_DATA_BITS)) activation_instance(
				.clk(clk),
				.reset(reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.activation_enable(pipe_act_enable),
				.activation_func(pipe_act_func),
				.unbiased_activation(pipe_rs[i]),
				.bias(pipe_rt[i]),
				.activation_out(act_out[i])
			);
			lsu #(
				.ADDR_BITS(DATA_MEM_ADDR_BITS),
				.DATA_BITS(DATA_MEM_DATA_BITS)
			) lsu_instance(
				.clk(clk),
				.reset(reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.decoded_mem_read_enable(pipe_mem_read_enable),
				.decoded_mem_write_enable(pipe_mem_write_enable),
				.rs(pipe_rs[i]),
				.rt(pipe_rt[i]),
				.mem_read_valid(data_mem_read_valid[i]),
				.mem_read_address(data_mem_read_address[i]),
				.mem_read_ready(data_mem_read_ready[i]),
				.mem_read_data(data_mem_read_data[i]),
				.mem_write_valid(data_mem_write_valid[i]),
				.mem_write_address(data_mem_write_address[i]),
				.mem_write_data(data_mem_write_data[i]),
				.mem_write_ready(data_mem_write_ready[i]),
				.lsu_state(lsu_state[i]),
				.lsu_out(lsu_out[i])
			);
			registers #(
				.THREADS_PER_BLOCK(THREADS_PER_BLOCK),
				.THREAD_ID(i),
				.DATA_BITS(DATA_MEM_DATA_BITS)
			) register_instance(
				.clk(clk),
				.reset(reset),
				.enable(i < thread_count),
				.block_id(block_id),
				.core_state(core_state),
				.decoded_reg_write_enable(pipe_reg_write_enable),
				.decoded_reg_input_mux(pipe_reg_input_mux),
				.decoded_rd_address(decoded_rd_address),
				.decoded_rs_address(decoded_rs_address),
				.decoded_rt_address(decoded_rt_address),
				.write_rd_address(pipe_rd_address),
				.decoded_immediate(pipe_immediate),
				.alu_out(alu_out[i]),
				.lsu_out(lsu_out[i]),
				.fma_out(fma_out[i]),
				.act_out(act_out[i]),
				.systolic_out(systolic_out[i]),
				.rs(rs[i]),
				.rt(rt[i]),
				.rd_data(rd_data[i])
			);
			pc #(
				.DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
				.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
			) pc_instance(
				.clk(clk),
				.reset(reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.decoded_nzp(pipe_nzp),
				.decoded_nzp_write_enable(pipe_nzp_write_enable),
				.decoded_pc_mux(pipe_pc_mux),
				.alu_out(alu_out[i][2:0]),
				.current_pc(current_pc),
				.next_pc(next_pc[i]),
				.branch_taken(per_thread_branch_taken[i]),
				.instruction(instruction[8:0])
			);
		end
	endgenerate
	localparam [1:0] SYSTOLIC_OP_CLEAR = 2'b00;
	localparam [1:0] SYSTOLIC_OP_LOAD = 2'b01;
	localparam [1:0] SYSTOLIC_OP_COMPUTE = 2'b10;
	localparam [31:0] FMA_VISIBLE_LATENCY = 3;
	localparam [31:0] SYSTOLIC_DRAIN_CYCLES = SYSTOLIC_SIZE + FMA_VISIBLE_LATENCY;
	localparam [31:0] SYSTOLIC_RESULT_COUNT = SYSTOLIC_SIZE * SYSTOLIC_SIZE;
	wire systolic_exec = (core_state == 3'b101) && pipe_systolic_enable;
	wire systolic_clear_acc = systolic_exec && (pipe_systolic_op == SYSTOLIC_OP_CLEAR);
	wire systolic_load_weights = systolic_exec && (pipe_systolic_op == SYSTOLIC_OP_LOAD);
	wire systolic_compute_enable = systolic_exec && (pipe_systolic_op == SYSTOLIC_OP_COMPUTE);
	reg [SYSTOLIC_DRAIN_CYCLES - 1:0] systolic_compute_drain;
	wire systolic_enable = ((systolic_clear_acc || systolic_load_weights) || systolic_compute_enable) || |systolic_compute_drain;
	always @(posedge clk)
		if (reset)
			systolic_compute_drain <= {SYSTOLIC_DRAIN_CYCLES {1'b0}};
		else begin
			systolic_compute_drain[0] <= systolic_compute_enable;
			systolic_compute_drain[SYSTOLIC_DRAIN_CYCLES - 1:1] <= systolic_compute_drain[SYSTOLIC_DRAIN_CYCLES - 2:0];
		end
	wire [(DATA_MEM_DATA_BITS * SYSTOLIC_SIZE) - 1:0] systolic_a_inputs_flat [NUM_SYSTOLIC_ARRAYS - 1:0];
	wire [(DATA_MEM_DATA_BITS * SYSTOLIC_SIZE) - 1:0] systolic_b_inputs_flat [NUM_SYSTOLIC_ARRAYS - 1:0];
	wire [(DATA_MEM_DATA_BITS * SYSTOLIC_RESULT_COUNT) - 1:0] systolic_results_flat [NUM_SYSTOLIC_ARRAYS - 1:0];
	wire [NUM_SYSTOLIC_ARRAYS - 1:0] systolic_ready;
	genvar _gv_arr_idx_1;
	genvar _gv_elem_idx_1;
	generate
		for (_gv_arr_idx_1 = 0; _gv_arr_idx_1 < NUM_SYSTOLIC_ARRAYS; _gv_arr_idx_1 = _gv_arr_idx_1 + 1) begin : input_map
			localparam arr_idx = _gv_arr_idx_1;
			for (_gv_elem_idx_1 = 0; _gv_elem_idx_1 < SYSTOLIC_SIZE; _gv_elem_idx_1 = _gv_elem_idx_1 + 1) begin : elem_map
				localparam elem_idx = _gv_elem_idx_1;
				localparam signed [31:0] thread_idx = (arr_idx * SYSTOLIC_SIZE) + elem_idx;
				if (thread_idx < THREADS_PER_BLOCK) begin : active_thread
					assign systolic_a_inputs_flat[arr_idx][elem_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = pipe_rs[thread_idx];
					assign systolic_b_inputs_flat[arr_idx][elem_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = pipe_rt[thread_idx];
				end
				else begin : inactive_thread
					assign systolic_a_inputs_flat[arr_idx][elem_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = {DATA_MEM_DATA_BITS {1'b0}};
					assign systolic_b_inputs_flat[arr_idx][elem_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = {DATA_MEM_DATA_BITS {1'b0}};
				end
			end
		end
	endgenerate
	integer systolic_result_idx;
	always @(*)
		for (systolic_result_idx = 0; systolic_result_idx < THREADS_PER_BLOCK; systolic_result_idx = systolic_result_idx + 1)
			if (systolic_result_idx < SYSTOLIC_RESULT_COUNT) begin
				if (pipe_systolic_idx < NUM_SYSTOLIC_ARRAYS)
					systolic_out[systolic_result_idx] = systolic_results_flat[pipe_systolic_idx][systolic_result_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS];
				else
					systolic_out[systolic_result_idx] = {DATA_MEM_DATA_BITS {1'b0}};
			end
			else
				systolic_out[systolic_result_idx] = {DATA_MEM_DATA_BITS {1'b0}};
	genvar _gv_k_1;
	generate
		for (_gv_k_1 = 0; _gv_k_1 < NUM_SYSTOLIC_ARRAYS; _gv_k_1 = _gv_k_1 + 1) begin : systolic_arrays
			localparam k = _gv_k_1;
			systolic_array #(
				.DATA_BITS(DATA_MEM_DATA_BITS),
				.ARRAY_SIZE(SYSTOLIC_SIZE),
				.PIPE_INTERVAL(SYSTOLIC_SIZE)
			) systolic_array_inst(
				.clk(clk),
				.reset(reset),
				.enable(systolic_enable),
				.clear_acc(systolic_clear_acc),
				.load_weights(systolic_load_weights),
				.compute_enable(systolic_compute_enable),
				.a_inputs_flat(systolic_a_inputs_flat[k]),
				.b_inputs_flat(systolic_b_inputs_flat[k]),
				.results_flat(systolic_results_flat[k]),
				.ready(systolic_ready[k])
			);
		end
	endgenerate
endmodule
`default_nettype none
module dcr (
	clk,
	reset,
	device_control_write_enable,
	device_control_data,
	thread_count
);
	input wire clk;
	input wire reset;
	input wire device_control_write_enable;
	input wire [7:0] device_control_data;
	output wire [7:0] thread_count;
	reg [7:0] device_conrol_register;
	assign thread_count = device_conrol_register[7:0];
	always @(posedge clk)
		if (reset)
			device_conrol_register <= 8'b00000000;
		else if (device_control_write_enable)
			device_conrol_register <= device_control_data;
endmodule
`default_nettype none
module decoder (
	clk,
	reset,
	core_state,
	instruction,
	decoded_rd_address,
	decoded_rs_address,
	decoded_rt_address,
	decoded_nzp,
	decoded_immediate,
	decoded_reg_write_enable,
	decoded_mem_read_enable,
	decoded_mem_write_enable,
	decoded_nzp_write_enable,
	decoded_reg_input_mux,
	decoded_alu_arithmetic_mux,
	decoded_alu_output_mux,
	decoded_pc_mux,
	decoded_fma_enable,
	decoded_act_enable,
	decoded_act_func,
	decoded_systolic_enable,
	decoded_systolic_op,
	decoded_systolic_idx,
	decoded_branch,
	decoded_ret
);
	input wire clk;
	input wire reset;
	input wire [2:0] core_state;
	input wire [15:0] instruction;
	output reg [3:0] decoded_rd_address;
	output reg [3:0] decoded_rs_address;
	output reg [3:0] decoded_rt_address;
	output reg [2:0] decoded_nzp;
	output reg [7:0] decoded_immediate;
	output reg decoded_reg_write_enable;
	output reg decoded_mem_read_enable;
	output reg decoded_mem_write_enable;
	output reg decoded_nzp_write_enable;
	output reg [2:0] decoded_reg_input_mux;
	output reg [1:0] decoded_alu_arithmetic_mux;
	output reg decoded_alu_output_mux;
	output reg decoded_pc_mux;
	output reg decoded_fma_enable;
	output reg decoded_act_enable;
	output reg [1:0] decoded_act_func;
	output reg decoded_systolic_enable;
	output reg [1:0] decoded_systolic_op;
	output reg decoded_systolic_idx;
	output reg decoded_branch;
	output reg decoded_ret;
	localparam NOP = 4'b0000;
	localparam BRnzp = 4'b0001;
	localparam CMP = 4'b0010;
	localparam ADD = 4'b0011;
	localparam SUB = 4'b0100;
	localparam MUL = 4'b0101;
	localparam DIV = 4'b0110;
	localparam LDR = 4'b0111;
	localparam STR = 4'b1000;
	localparam CONST = 4'b1001;
	localparam FMA = 4'b1010;
	localparam ACT = 4'b1011;
	localparam SYS = 4'b1100;
	localparam RET = 4'b1111;
	always @(*)
		if (reset) begin
			decoded_rd_address = 0;
			decoded_rs_address = 0;
			decoded_rt_address = 0;
			decoded_immediate = 0;
			decoded_nzp = 0;
			decoded_reg_write_enable = 0;
			decoded_mem_read_enable = 0;
			decoded_mem_write_enable = 0;
			decoded_nzp_write_enable = 0;
			decoded_reg_input_mux = 0;
			decoded_alu_arithmetic_mux = 0;
			decoded_alu_output_mux = 0;
			decoded_pc_mux = 0;
			decoded_fma_enable = 0;
			decoded_branch = 0;
			decoded_act_enable = 0;
			decoded_act_func = 0;
			decoded_systolic_enable = 0;
			decoded_systolic_op = 0;
			decoded_systolic_idx = 0;
			decoded_ret = 0;
		end
		else begin
			decoded_rd_address = instruction[11:8];
			decoded_rs_address = instruction[7:4];
			decoded_rt_address = instruction[3:0];
			decoded_immediate = instruction[7:0];
			decoded_nzp = instruction[11:9];
			decoded_reg_write_enable = 0;
			decoded_mem_read_enable = 0;
			decoded_mem_write_enable = 0;
			decoded_nzp_write_enable = 0;
			decoded_reg_input_mux = 0;
			decoded_alu_arithmetic_mux = 0;
			decoded_alu_output_mux = 0;
			decoded_pc_mux = 0;
			decoded_fma_enable = 0;
			decoded_act_enable = 0;
			decoded_act_func = 0;
			decoded_systolic_enable = 0;
			decoded_systolic_op = 0;
			decoded_systolic_idx = 0;
			decoded_ret = 0;
			decoded_branch = 0;
			case (instruction[15:12])
				NOP:
					;
				BRnzp: begin
					decoded_pc_mux = 1;
					decoded_branch = 1;
				end
				CMP: begin
					decoded_rs_address = instruction[11:8];
					decoded_rt_address = instruction[7:4];
					decoded_alu_output_mux = 1;
					decoded_nzp_write_enable = 1;
				end
				ADD: begin
					decoded_reg_write_enable = 1;
					decoded_reg_input_mux = 3'b000;
					decoded_alu_arithmetic_mux = 2'b00;
				end
				SUB: begin
					decoded_reg_write_enable = 1;
					decoded_reg_input_mux = 3'b000;
					decoded_alu_arithmetic_mux = 2'b01;
				end
				MUL: begin
					decoded_reg_write_enable = 1;
					decoded_reg_input_mux = 3'b000;
					decoded_alu_arithmetic_mux = 2'b10;
				end
				DIV: begin
					decoded_reg_write_enable = 1;
					decoded_reg_input_mux = 3'b000;
					decoded_alu_arithmetic_mux = 2'b11;
				end
				LDR: begin
					decoded_reg_write_enable = 1;
					decoded_reg_input_mux = 3'b001;
					decoded_mem_read_enable = 1;
				end
				STR: begin
					decoded_rs_address = instruction[11:8];
					decoded_rt_address = instruction[7:4];
					decoded_mem_write_enable = 1;
				end
				CONST: begin
					decoded_reg_write_enable = 1;
					decoded_reg_input_mux = 3'b010;
				end
				FMA: begin
					decoded_reg_write_enable = 1;
					decoded_reg_input_mux = 3'b011;
					decoded_fma_enable = 1;
				end
				ACT: begin
					decoded_reg_write_enable = 1;
					decoded_reg_input_mux = 3'b100;
					decoded_act_enable = 1;
					decoded_act_func = instruction[9:8];
				end
				SYS: begin
					decoded_rs_address = 4'd0;
					decoded_rt_address = 4'd1;
					decoded_systolic_enable = 1;
					decoded_systolic_op = instruction[7:6];
					decoded_systolic_idx = instruction[0];
					if (instruction[7:6] == 2'b11) begin
						decoded_reg_write_enable = 1;
						decoded_reg_input_mux = 3'b101;
					end
				end
				RET: decoded_ret = 1;
				default:
					;
			endcase
		end
endmodule
`default_nettype none
module dispatch (
	clk,
	reset,
	start,
	thread_count,
	core_done,
	core_start,
	core_reset,
	core_block_id_flat,
	core_thread_count_flat,
	done
);
	parameter NUM_CORES = 2;
	parameter THREADS_PER_BLOCK = 4;
	input wire clk;
	input wire reset;
	input wire start;
	input wire [7:0] thread_count;
	input wire [NUM_CORES - 1:0] core_done;
	output reg [NUM_CORES - 1:0] core_start;
	output reg [NUM_CORES - 1:0] core_reset;
	output reg [(8 * NUM_CORES) - 1:0] core_block_id_flat;
	output reg [(($clog2(THREADS_PER_BLOCK) + 1) * NUM_CORES) - 1:0] core_thread_count_flat;
	output reg done;
	reg [7:0] core_block_id [NUM_CORES - 1:0];
	reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES - 1:0];
	localparam TC_BITS = $clog2(THREADS_PER_BLOCK) + 1;
	wire [7:0] total_blocks;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	assign total_blocks = sv2v_cast_8(((sv2v_cast_32(thread_count) + THREADS_PER_BLOCK) - 1) / THREADS_PER_BLOCK);
	reg [7:0] blocks_dispatched;
	reg [7:0] blocks_done;
	reg start_execution;
	integer i;
	genvar _gv_g_1;
	generate
		for (_gv_g_1 = 0; _gv_g_1 < NUM_CORES; _gv_g_1 = _gv_g_1 + 1) begin : flatten_outputs
			localparam g = _gv_g_1;
			always @(*) begin
				core_block_id_flat[((g + 1) * 8) - 1-:8] = core_block_id[g];
				core_thread_count_flat[((g + 1) * TC_BITS) - 1-:TC_BITS] = core_thread_count[g];
			end
		end
	endgenerate
	function automatic signed [TC_BITS - 1:0] sv2v_cast_9FF7A_signed;
		input reg signed [TC_BITS - 1:0] inp;
		sv2v_cast_9FF7A_signed = inp;
	endfunction
	function automatic [TC_BITS - 1:0] sv2v_cast_9FF7A;
		input reg [TC_BITS - 1:0] inp;
		sv2v_cast_9FF7A = inp;
	endfunction
	always @(posedge clk)
		if (reset) begin
			done <= 0;
			blocks_dispatched <= 0;
			blocks_done <= 0;
			start_execution <= 0;
			for (i = 0; i < NUM_CORES; i = i + 1)
				begin
					core_start[i] <= 0;
					core_reset[i] <= 1;
					core_block_id[i] <= 0;
					core_thread_count[i] <= sv2v_cast_9FF7A_signed(THREADS_PER_BLOCK);
				end
		end
		else if (start) begin
			if (!start_execution) begin
				start_execution <= 1;
				for (i = 0; i < NUM_CORES; i = i + 1)
					core_reset[i] <= 1;
			end
			if (blocks_done == total_blocks)
				done <= 1;
			begin : dispatch_block
				reg [7:0] next_dispatched;
				next_dispatched = blocks_dispatched;
				for (i = 0; i < NUM_CORES; i = i + 1)
					if (core_reset[i]) begin
						core_reset[i] <= 0;
						if (next_dispatched < total_blocks) begin
							core_start[i] <= 1;
							core_block_id[i] <= next_dispatched;
							core_thread_count[i] <= (next_dispatched == (total_blocks - 1) ? sv2v_cast_9FF7A(sv2v_cast_32(thread_count) - (sv2v_cast_32(next_dispatched) * THREADS_PER_BLOCK)) : sv2v_cast_9FF7A_signed(THREADS_PER_BLOCK));
							next_dispatched = next_dispatched + 1;
						end
					end
				blocks_dispatched <= next_dispatched;
			end
			begin : done_block
				reg [7:0] next_done;
				next_done = blocks_done;
				for (i = 0; i < NUM_CORES; i = i + 1)
					if (core_start[i] && core_done[i]) begin
						core_reset[i] <= 1;
						core_start[i] <= 0;
						next_done = next_done + 1;
					end
				blocks_done <= next_done;
			end
		end
endmodule
`default_nettype none
module fetcher (
	clk,
	reset,
	core_state,
	current_pc,
	mem_read_valid,
	mem_read_address,
	mem_read_ready,
	mem_read_data,
	fetcher_state,
	instruction
);
	parameter PROGRAM_MEM_ADDR_BITS = 8;
	parameter PROGRAM_MEM_DATA_BITS = 16;
	input wire clk;
	input wire reset;
	input wire [2:0] core_state;
	input wire [PROGRAM_MEM_ADDR_BITS - 1:0] current_pc;
	output reg mem_read_valid;
	output reg [PROGRAM_MEM_ADDR_BITS - 1:0] mem_read_address;
	input wire mem_read_ready;
	input wire [PROGRAM_MEM_DATA_BITS - 1:0] mem_read_data;
	output reg [2:0] fetcher_state;
	output reg [PROGRAM_MEM_DATA_BITS - 1:0] instruction;
	localparam IDLE = 3'b000;
	localparam FETCHING = 3'b001;
	localparam FETCHED = 3'b010;
	always @(posedge clk)
		if (reset) begin
			fetcher_state <= IDLE;
			mem_read_valid <= 0;
			mem_read_address <= 0;
			instruction <= {PROGRAM_MEM_DATA_BITS {1'b0}};
		end
		else
			case (fetcher_state)
				IDLE:
					if (core_state == 3'b001) begin
						fetcher_state <= FETCHING;
						mem_read_valid <= 1;
						mem_read_address <= current_pc;
					end
				FETCHING:
					if (mem_read_ready) begin
						fetcher_state <= FETCHED;
						instruction <= mem_read_data;
						mem_read_valid <= 0;
					end
				FETCHED:
					if (core_state == 3'b010)
						fetcher_state <= IDLE;
				default: begin
					fetcher_state <= IDLE;
					mem_read_valid <= 0;
				end
			endcase
endmodule
`default_nettype none
module fma (
	clk,
	reset,
	enable,
	core_state,
	decoded_fma_enable,
	rs,
	rt,
	rq,
	fma_out
);
	parameter DATA_BITS = 16;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [2:0] core_state;
	input wire decoded_fma_enable;
	input wire [DATA_BITS - 1:0] rs;
	input wire [DATA_BITS - 1:0] rt;
	input wire [DATA_BITS - 1:0] rq;
	output wire [DATA_BITS - 1:0] fma_out;
	localparam [DATA_BITS - 1:0] Q115_MAX = 16'h7fff;
	localparam [DATA_BITS - 1:0] Q115_MIN = 16'hffff;
	localparam [DATA_BITS - 1:0] NEG_ZERO = 16'h8000;
	localparam signed [31:0] Q115_MAX_S32 = 32'sd32767;
	localparam signed [31:0] Q115_MIN_S32 = -32'sd32767;
	reg [DATA_BITS - 1:0] r3_weighted;
	reg [DATA_BITS - 1:0] fma_out_reg;
	assign fma_out = fma_out_reg;
	wire sign_r1 = rs[15];
	wire sign_r2 = rt[15];
	wire sign_product = sign_r1 ^ sign_r2;
	wire [14:0] mag_r1 = rs[14:0];
	wire [14:0] mag_r2 = rt[14:0];
	wire [29:0] product_unsigned = mag_r1 * mag_r2;
	wire [14:0] product_mag = product_unsigned[29:15];
	wire [DATA_BITS - 1:0] product_sm = {sign_product, product_mag};
	wire [DATA_BITS - 1:0] product_saturated = (product_mag == 15'b000000000000000 ? {DATA_BITS {1'b0}} : product_sm);
	wire signed [15:0] r4_signed = (rq[15] ? -$signed({1'b0, rq[14:0]}) : $signed({1'b0, rq[14:0]}));
	wire signed [15:0] r3_signed = (r3_weighted[15] ? -$signed({1'b0, r3_weighted[14:0]}) : $signed({1'b0, r3_weighted[14:0]}));
	wire signed [16:0] acc_sum_ext = {r4_signed[15], r4_signed} + {r3_signed[15], r3_signed};
	wire signed [15:0] acc_sum_sat = (acc_sum_ext > 32767 ? 16'sd32767 : (acc_sum_ext < -32767 ? -16'sd32767 : acc_sum_ext[15:0]));
	wire [15:0] abs_acc_sum_sat = -acc_sum_sat;
	wire [DATA_BITS - 1:0] acc_sm = (acc_sum_sat < 0 ? {1'b1, abs_acc_sum_sat[14:0]} : {1'b0, acc_sum_sat[14:0]});
	wire [DATA_BITS - 1:0] accumulated_saturated = (acc_sm == NEG_ZERO ? {DATA_BITS {1'b0}} : acc_sm);
	reg exec_phase;
	always @(posedge clk)
		if (reset) begin
			r3_weighted <= {DATA_BITS {1'b0}};
			fma_out_reg <= {DATA_BITS {1'b0}};
			exec_phase <= 1'b0;
		end
		else if (enable) begin
			if ((core_state != 3'b101) || !decoded_fma_enable)
				exec_phase <= 1'b0;
			if ((core_state == 3'b101) && decoded_fma_enable) begin
				if (!exec_phase) begin
					r3_weighted <= product_saturated;
					exec_phase <= 1'b1;
				end
				else begin
					fma_out_reg <= accumulated_saturated;
					exec_phase <= 1'b0;
				end
			end
		end
endmodule
`default_nettype none
module gpu (
	clk,
	reset,
	start,
	done,
	device_control_write_enable,
	device_control_data,
	program_mem_read_valid,
	program_mem_read_address_flat,
	program_mem_read_ready,
	program_mem_read_data_flat,
	data_mem_read_valid,
	data_mem_read_address_flat,
	data_mem_read_ready,
	data_mem_read_data_flat,
	data_mem_write_valid,
	data_mem_write_address_flat,
	data_mem_write_data_flat,
	data_mem_write_ready
);
	parameter DATA_MEM_ADDR_BITS = 19;
	parameter DATA_MEM_DATA_BITS = 16;
	parameter DATA_MEM_NUM_CHANNELS = 8;
	parameter PROGRAM_MEM_ADDR_BITS = 9;
	parameter PROGRAM_MEM_DATA_BITS = 16;
	parameter PROGRAM_MEM_NUM_CHANNELS = 2;
	parameter NUM_CORES = 2;
	parameter THREADS_PER_BLOCK = 4;
	parameter SYSTOLIC_SIZE = 2;
	parameter NUM_SYSTOLIC_ARRAYS = 2;
	parameter CACHE_SIZE = 4;
	input wire clk;
	input wire reset;
	input wire start;
	output wire done;
	input wire device_control_write_enable;
	input wire [7:0] device_control_data;
	output wire [PROGRAM_MEM_NUM_CHANNELS - 1:0] program_mem_read_valid;
	output wire [(PROGRAM_MEM_ADDR_BITS * PROGRAM_MEM_NUM_CHANNELS) - 1:0] program_mem_read_address_flat;
	input wire [PROGRAM_MEM_NUM_CHANNELS - 1:0] program_mem_read_ready;
	input wire [(PROGRAM_MEM_DATA_BITS * PROGRAM_MEM_NUM_CHANNELS) - 1:0] program_mem_read_data_flat;
	output wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_read_valid;
	output wire [(DATA_MEM_ADDR_BITS * DATA_MEM_NUM_CHANNELS) - 1:0] data_mem_read_address_flat;
	input wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_read_ready;
	input wire [(DATA_MEM_DATA_BITS * DATA_MEM_NUM_CHANNELS) - 1:0] data_mem_read_data_flat;
	output wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_write_valid;
	output wire [(DATA_MEM_ADDR_BITS * DATA_MEM_NUM_CHANNELS) - 1:0] data_mem_write_address_flat;
	output wire [(DATA_MEM_DATA_BITS * DATA_MEM_NUM_CHANNELS) - 1:0] data_mem_write_data_flat;
	input wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_write_ready;
	reg reset_pipe1;
	reg reset_pipe2;
	always @(posedge clk) begin
		reset_pipe1 <= reset;
		reset_pipe2 <= reset_pipe1;
	end
	wire [7:0] thread_count;
	wire [NUM_CORES - 1:0] core_start;
	wire [NUM_CORES - 1:0] core_reset;
	wire [NUM_CORES - 1:0] core_done;
	wire [(8 * NUM_CORES) - 1:0] core_block_id_flat;
	localparam TC_BITS = $clog2(THREADS_PER_BLOCK) + 1;
	wire [(TC_BITS * NUM_CORES) - 1:0] core_thread_count_flat;
	wire [7:0] core_block_id [NUM_CORES - 1:0];
	wire [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES - 1:0];
	genvar _gv_blk_idx_1;
	generate
		for (_gv_blk_idx_1 = 0; _gv_blk_idx_1 < NUM_CORES; _gv_blk_idx_1 = _gv_blk_idx_1 + 1) begin : unflatten_dispatch
			localparam blk_idx = _gv_blk_idx_1;
			assign core_block_id[blk_idx] = core_block_id_flat[((blk_idx + 1) * 8) - 1-:8];
			assign core_thread_count[blk_idx] = core_thread_count_flat[((blk_idx + 1) * TC_BITS) - 1-:TC_BITS];
		end
	endgenerate
	localparam NUM_LSUS = NUM_CORES * THREADS_PER_BLOCK;
	wire [NUM_LSUS - 1:0] lsu_read_valid;
	wire [(DATA_MEM_ADDR_BITS * NUM_LSUS) - 1:0] lsu_read_address_flat;
	wire [NUM_LSUS - 1:0] lsu_read_ready;
	wire [(DATA_MEM_DATA_BITS * NUM_LSUS) - 1:0] lsu_read_data_flat;
	wire [NUM_LSUS - 1:0] lsu_write_valid;
	wire [(DATA_MEM_ADDR_BITS * NUM_LSUS) - 1:0] lsu_write_address_flat;
	wire [(DATA_MEM_DATA_BITS * NUM_LSUS) - 1:0] lsu_write_data_flat;
	wire [NUM_LSUS - 1:0] lsu_write_ready;
	wire [DATA_MEM_ADDR_BITS - 1:0] lsu_read_address [NUM_LSUS - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] lsu_read_data [NUM_LSUS - 1:0];
	wire [DATA_MEM_ADDR_BITS - 1:0] lsu_write_address [NUM_LSUS - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] lsu_write_data [NUM_LSUS - 1:0];
	genvar _gv_lsu_idx_1;
	generate
		for (_gv_lsu_idx_1 = 0; _gv_lsu_idx_1 < NUM_LSUS; _gv_lsu_idx_1 = _gv_lsu_idx_1 + 1) begin : lsu_flatten_unflatten
			localparam lsu_idx = _gv_lsu_idx_1;
			assign lsu_read_data[lsu_idx] = lsu_read_data_flat[((lsu_idx + 1) * DATA_MEM_DATA_BITS) - 1:lsu_idx * DATA_MEM_DATA_BITS];
			assign lsu_read_address_flat[((lsu_idx + 1) * DATA_MEM_ADDR_BITS) - 1:lsu_idx * DATA_MEM_ADDR_BITS] = lsu_read_address[lsu_idx];
			assign lsu_write_address_flat[((lsu_idx + 1) * DATA_MEM_ADDR_BITS) - 1:lsu_idx * DATA_MEM_ADDR_BITS] = lsu_write_address[lsu_idx];
			assign lsu_write_data_flat[((lsu_idx + 1) * DATA_MEM_DATA_BITS) - 1:lsu_idx * DATA_MEM_DATA_BITS] = lsu_write_data[lsu_idx];
		end
	endgenerate
	localparam NUM_FETCHERS = NUM_CORES;
	wire [NUM_FETCHERS - 1:0] fetcher_read_valid;
	wire [(PROGRAM_MEM_ADDR_BITS * NUM_FETCHERS) - 1:0] fetcher_read_address_flat;
	wire [NUM_FETCHERS - 1:0] fetcher_read_ready;
	wire [(PROGRAM_MEM_DATA_BITS * NUM_FETCHERS) - 1:0] fetcher_read_data_flat;
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] fetcher_read_address [NUM_FETCHERS - 1:0];
	wire [PROGRAM_MEM_DATA_BITS - 1:0] fetcher_read_data [NUM_FETCHERS - 1:0];
	genvar _gv_f_idx_1;
	generate
		for (_gv_f_idx_1 = 0; _gv_f_idx_1 < NUM_FETCHERS; _gv_f_idx_1 = _gv_f_idx_1 + 1) begin : fetcher_flatten
			localparam f_idx = _gv_f_idx_1;
			assign fetcher_read_address_flat[((f_idx + 1) * PROGRAM_MEM_ADDR_BITS) - 1:f_idx * PROGRAM_MEM_ADDR_BITS] = fetcher_read_address[f_idx];
			assign fetcher_read_data[f_idx] = fetcher_read_data_flat[((f_idx + 1) * PROGRAM_MEM_DATA_BITS) - 1:f_idx * PROGRAM_MEM_DATA_BITS];
		end
	endgenerate
	wire [NUM_FETCHERS - 1:0] prog_mem_write_ready_unused;
	wire [PROGRAM_MEM_NUM_CHANNELS - 1:0] prog_ext_write_valid_unused;
	wire [(PROGRAM_MEM_ADDR_BITS * PROGRAM_MEM_NUM_CHANNELS) - 1:0] prog_ext_write_address_flat_unused;
	wire [(PROGRAM_MEM_DATA_BITS * PROGRAM_MEM_NUM_CHANNELS) - 1:0] prog_ext_write_data_flat_unused;
	wire [(PROGRAM_MEM_ADDR_BITS * NUM_FETCHERS) - 1:0] fetcher_write_address_flat_unused;
	wire [(PROGRAM_MEM_DATA_BITS * NUM_FETCHERS) - 1:0] fetcher_write_data_flat_unused;
	assign fetcher_write_address_flat_unused = {PROGRAM_MEM_ADDR_BITS * NUM_FETCHERS {1'b0}};
	assign fetcher_write_data_flat_unused = {PROGRAM_MEM_DATA_BITS * NUM_FETCHERS {1'b0}};
	dcr dcr_instance(
		.clk(clk),
		.reset(reset_pipe2),
		.device_control_write_enable(device_control_write_enable),
		.device_control_data(device_control_data),
		.thread_count(thread_count)
	);
	controller #(
		.ADDR_BITS(DATA_MEM_ADDR_BITS),
		.DATA_BITS(DATA_MEM_DATA_BITS),
		.NUM_CONSUMERS(NUM_LSUS),
		.NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
	) data_mem_controller(
		.clk(clk),
		.reset(reset_pipe2),
		.consumer_read_valid(lsu_read_valid),
		.consumer_read_address_flat(lsu_read_address_flat),
		.consumer_read_ready(lsu_read_ready),
		.consumer_read_data_flat(lsu_read_data_flat),
		.consumer_write_valid(lsu_write_valid),
		.consumer_write_address_flat(lsu_write_address_flat),
		.consumer_write_data_flat(lsu_write_data_flat),
		.consumer_write_ready(lsu_write_ready),
		.mem_read_valid(data_mem_read_valid),
		.mem_read_address_flat(data_mem_read_address_flat),
		.mem_read_ready(data_mem_read_ready),
		.mem_read_data_flat(data_mem_read_data_flat),
		.mem_write_valid(data_mem_write_valid),
		.mem_write_address_flat(data_mem_write_address_flat),
		.mem_write_data_flat(data_mem_write_data_flat),
		.mem_write_ready(data_mem_write_ready)
	);
	controller #(
		.ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
		.DATA_BITS(PROGRAM_MEM_DATA_BITS),
		.NUM_CONSUMERS(NUM_CORES),
		.NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS)
	) program_mem_controller(
		.clk(clk),
		.reset(reset_pipe2),
		.consumer_read_valid(fetcher_read_valid),
		.consumer_read_address_flat(fetcher_read_address_flat),
		.consumer_read_ready(fetcher_read_ready),
		.consumer_read_data_flat(fetcher_read_data_flat),
		.consumer_write_valid({NUM_FETCHERS {1'b0}}),
		.consumer_write_address_flat(fetcher_write_address_flat_unused),
		.consumer_write_data_flat(fetcher_write_data_flat_unused),
		.consumer_write_ready(prog_mem_write_ready_unused),
		.mem_read_valid(program_mem_read_valid),
		.mem_read_address_flat(program_mem_read_address_flat),
		.mem_read_ready(program_mem_read_ready),
		.mem_read_data_flat(program_mem_read_data_flat),
		.mem_write_valid(prog_ext_write_valid_unused),
		.mem_write_address_flat(prog_ext_write_address_flat_unused),
		.mem_write_data_flat(prog_ext_write_data_flat_unused),
		.mem_write_ready({PROGRAM_MEM_NUM_CHANNELS {1'b0}})
	);
	dispatch #(
		.NUM_CORES(NUM_CORES),
		.THREADS_PER_BLOCK(THREADS_PER_BLOCK)
	) dispatch_instance(
		.clk(clk),
		.reset(reset_pipe2),
		.start(start),
		.thread_count(thread_count),
		.core_done(core_done),
		.core_start(core_start),
		.core_reset(core_reset),
		.core_block_id_flat(core_block_id_flat),
		.core_thread_count_flat(core_thread_count_flat),
		.done(done)
	);
	genvar _gv_i_2;
	generate
		for (_gv_i_2 = 0; _gv_i_2 < NUM_CORES; _gv_i_2 = _gv_i_2 + 1) begin : cores
			localparam i = _gv_i_2;
			wire [THREADS_PER_BLOCK - 1:0] core_lsu_read_valid;
			wire [(DATA_MEM_ADDR_BITS * THREADS_PER_BLOCK) - 1:0] core_lsu_read_address_flat;
			wire [THREADS_PER_BLOCK - 1:0] core_lsu_read_ready;
			wire [(DATA_MEM_DATA_BITS * THREADS_PER_BLOCK) - 1:0] core_lsu_read_data_flat;
			wire [THREADS_PER_BLOCK - 1:0] core_lsu_write_valid;
			wire [(DATA_MEM_ADDR_BITS * THREADS_PER_BLOCK) - 1:0] core_lsu_write_address_flat;
			wire [(DATA_MEM_DATA_BITS * THREADS_PER_BLOCK) - 1:0] core_lsu_write_data_flat;
			wire [THREADS_PER_BLOCK - 1:0] core_lsu_write_ready;
			wire [DATA_MEM_ADDR_BITS - 1:0] core_lsu_read_address [THREADS_PER_BLOCK - 1:0];
			wire [DATA_MEM_DATA_BITS - 1:0] core_lsu_read_data [THREADS_PER_BLOCK - 1:0];
			wire [DATA_MEM_ADDR_BITS - 1:0] core_lsu_write_address [THREADS_PER_BLOCK - 1:0];
			wire [DATA_MEM_DATA_BITS - 1:0] core_lsu_write_data [THREADS_PER_BLOCK - 1:0];
			wire [2:0] core_state_for_decode;
			wire [15:0] core_instruction;
			wire [3:0] decoded_rd_address;
			wire [3:0] decoded_rs_address;
			wire [3:0] decoded_rt_address;
			wire [2:0] decoded_nzp;
			wire [7:0] decoded_immediate;
			wire decoded_reg_write_enable;
			wire decoded_mem_read_enable;
			wire decoded_mem_write_enable;
			wire decoded_nzp_write_enable;
			wire [2:0] decoded_reg_input_mux;
			wire [1:0] decoded_alu_arithmetic_mux;
			wire decoded_alu_output_mux;
			wire decoded_pc_mux;
			wire decoded_fma_enable;
			wire decoded_act_enable;
			wire [1:0] decoded_act_func;
			wire decoded_systolic_enable;
			wire [1:0] decoded_systolic_op;
			wire decoded_systolic_idx;
			wire decoded_branch;
			wire decoded_ret;
			genvar _gv_t_1;
			for (_gv_t_1 = 0; _gv_t_1 < THREADS_PER_BLOCK; _gv_t_1 = _gv_t_1 + 1) begin : unflatten_lsu
				localparam t = _gv_t_1;
				assign core_lsu_read_address[t] = core_lsu_read_address_flat[((t + 1) * DATA_MEM_ADDR_BITS) - 1:t * DATA_MEM_ADDR_BITS];
				assign core_lsu_write_address[t] = core_lsu_write_address_flat[((t + 1) * DATA_MEM_ADDR_BITS) - 1:t * DATA_MEM_ADDR_BITS];
				assign core_lsu_write_data[t] = core_lsu_write_data_flat[((t + 1) * DATA_MEM_DATA_BITS) - 1:t * DATA_MEM_DATA_BITS];
			end
			decoder decoder_instance(
				.clk(clk),
				.reset(reset_pipe2),
				.core_state(core_state_for_decode),
				.instruction(core_instruction),
				.decoded_rd_address(decoded_rd_address),
				.decoded_rs_address(decoded_rs_address),
				.decoded_rt_address(decoded_rt_address),
				.decoded_nzp(decoded_nzp),
				.decoded_immediate(decoded_immediate),
				.decoded_reg_write_enable(decoded_reg_write_enable),
				.decoded_mem_read_enable(decoded_mem_read_enable),
				.decoded_mem_write_enable(decoded_mem_write_enable),
				.decoded_nzp_write_enable(decoded_nzp_write_enable),
				.decoded_reg_input_mux(decoded_reg_input_mux),
				.decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
				.decoded_alu_output_mux(decoded_alu_output_mux),
				.decoded_pc_mux(decoded_pc_mux),
				.decoded_fma_enable(decoded_fma_enable),
				.decoded_act_enable(decoded_act_enable),
				.decoded_act_func(decoded_act_func),
				.decoded_systolic_enable(decoded_systolic_enable),
				.decoded_systolic_op(decoded_systolic_op),
				.decoded_systolic_idx(decoded_systolic_idx),
				.decoded_branch(decoded_branch),
				.decoded_ret(decoded_ret)
			);
			core #(
				.DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
				.DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
				.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
				.PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
				.THREADS_PER_BLOCK(THREADS_PER_BLOCK),
				.SYSTOLIC_SIZE(SYSTOLIC_SIZE),
				.NUM_SYSTOLIC_ARRAYS(NUM_SYSTOLIC_ARRAYS),
				.CACHE_SIZE(CACHE_SIZE)
			) core_instance(
				.clk(clk),
				.reset(core_reset[i]),
				.start(core_start[i]),
				.done(core_done[i]),
				.block_id(core_block_id[i]),
				.thread_count(core_thread_count[i]),
				.core_state_for_decode(core_state_for_decode),
				.instruction_for_decode(core_instruction),
				.decoded_rd_address(decoded_rd_address),
				.decoded_rs_address(decoded_rs_address),
				.decoded_rt_address(decoded_rt_address),
				.decoded_nzp(decoded_nzp),
				.decoded_immediate(decoded_immediate),
				.decoded_reg_write_enable(decoded_reg_write_enable),
				.decoded_mem_read_enable(decoded_mem_read_enable),
				.decoded_mem_write_enable(decoded_mem_write_enable),
				.decoded_nzp_write_enable(decoded_nzp_write_enable),
				.decoded_reg_input_mux(decoded_reg_input_mux),
				.decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
				.decoded_alu_output_mux(decoded_alu_output_mux),
				.decoded_pc_mux(decoded_pc_mux),
				.decoded_fma_enable(decoded_fma_enable),
				.decoded_act_enable(decoded_act_enable),
				.decoded_act_func(decoded_act_func),
				.decoded_systolic_enable(decoded_systolic_enable),
				.decoded_systolic_op(decoded_systolic_op),
				.decoded_systolic_idx(decoded_systolic_idx),
				.decoded_branch(decoded_branch),
				.decoded_ret(decoded_ret),
				.program_mem_read_valid(fetcher_read_valid[i]),
				.program_mem_read_address(fetcher_read_address[i]),
				.program_mem_read_ready(fetcher_read_ready[i]),
				.program_mem_read_data(fetcher_read_data[i]),
				.data_mem_read_valid(core_lsu_read_valid),
				.data_mem_read_address_flat(core_lsu_read_address_flat),
				.data_mem_read_ready(core_lsu_read_ready),
				.data_mem_read_data_flat(core_lsu_read_data_flat),
				.data_mem_write_valid(core_lsu_write_valid),
				.data_mem_write_address_flat(core_lsu_write_address_flat),
				.data_mem_write_data_flat(core_lsu_write_data_flat),
				.data_mem_write_ready(core_lsu_write_ready)
			);
			genvar _gv_t2_1;
			for (_gv_t2_1 = 0; _gv_t2_1 < THREADS_PER_BLOCK; _gv_t2_1 = _gv_t2_1 + 1) begin : lsu_passthrough_assign
				localparam t2 = _gv_t2_1;
				assign lsu_read_valid[(i * THREADS_PER_BLOCK) + t2] = core_lsu_read_valid[t2];
				assign lsu_read_address[(i * THREADS_PER_BLOCK) + t2] = core_lsu_read_address[t2];
				assign lsu_write_valid[(i * THREADS_PER_BLOCK) + t2] = core_lsu_write_valid[t2];
				assign lsu_write_address[(i * THREADS_PER_BLOCK) + t2] = core_lsu_write_address[t2];
				assign lsu_write_data[(i * THREADS_PER_BLOCK) + t2] = core_lsu_write_data[t2];
				assign core_lsu_read_ready[t2] = lsu_read_ready[(i * THREADS_PER_BLOCK) + t2];
				assign core_lsu_read_data[t2] = lsu_read_data[(i * THREADS_PER_BLOCK) + t2];
				assign core_lsu_write_ready[t2] = lsu_write_ready[(i * THREADS_PER_BLOCK) + t2];
			end
			for (_gv_t2_1 = 0; _gv_t2_1 < THREADS_PER_BLOCK; _gv_t2_1 = _gv_t2_1 + 1) begin : lsu_rd_flatten
				localparam t2 = _gv_t2_1;
				assign core_lsu_read_data_flat[t2 * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = core_lsu_read_data[t2];
			end
		end
	endgenerate
endmodule
`default_nettype none
module kv_cache (
	clk,
	reset,
	enable,
	clear_cache,
	append_mode,
	seq_position,
	cache_length,
	key_write_en,
	key_head_sel,
	key_dim_sel,
	key_data_in,
	value_write_en,
	value_head_sel,
	value_dim_sel,
	value_data_in,
	key_read_en,
	key_read_head,
	key_read_pos,
	key_read_dim,
	key_data_out,
	key_valid,
	value_read_en,
	value_read_head,
	value_read_pos,
	value_read_dim,
	value_data_out,
	value_valid,
	batch_read_en,
	batch_head_sel,
	batch_start_pos,
	batch_end_pos,
	batch_valid,
	batch_done,
	sliding_window_en,
	window_size,
	cache_full,
	oldest_position
);
	parameter DATA_BITS = 16;
	parameter NUM_HEADS = 4;
	parameter HEAD_DIM = 16;
	parameter MAX_SEQ_LEN = 256;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire clear_cache;
	input wire append_mode;
	input wire [$clog2(MAX_SEQ_LEN) - 1:0] seq_position;
	output reg [$clog2(MAX_SEQ_LEN) - 1:0] cache_length;
	input wire key_write_en;
	input wire [$clog2(NUM_HEADS) - 1:0] key_head_sel;
	input wire [$clog2(HEAD_DIM) - 1:0] key_dim_sel;
	input wire [DATA_BITS - 1:0] key_data_in;
	input wire value_write_en;
	input wire [$clog2(NUM_HEADS) - 1:0] value_head_sel;
	input wire [$clog2(HEAD_DIM) - 1:0] value_dim_sel;
	input wire [DATA_BITS - 1:0] value_data_in;
	input wire key_read_en;
	input wire [$clog2(NUM_HEADS) - 1:0] key_read_head;
	input wire [$clog2(MAX_SEQ_LEN) - 1:0] key_read_pos;
	input wire [$clog2(HEAD_DIM) - 1:0] key_read_dim;
	output reg [DATA_BITS - 1:0] key_data_out;
	output reg key_valid;
	input wire value_read_en;
	input wire [$clog2(NUM_HEADS) - 1:0] value_read_head;
	input wire [$clog2(MAX_SEQ_LEN) - 1:0] value_read_pos;
	input wire [$clog2(HEAD_DIM) - 1:0] value_read_dim;
	output reg [DATA_BITS - 1:0] value_data_out;
	output reg value_valid;
	input wire batch_read_en;
	input wire [$clog2(NUM_HEADS) - 1:0] batch_head_sel;
	input wire [$clog2(MAX_SEQ_LEN) - 1:0] batch_start_pos;
	input wire [$clog2(MAX_SEQ_LEN) - 1:0] batch_end_pos;
	output reg batch_valid;
	output reg batch_done;
	input wire sliding_window_en;
	input wire [$clog2(MAX_SEQ_LEN) - 1:0] window_size;
	output reg cache_full;
	output reg [$clog2(MAX_SEQ_LEN) - 1:0] oldest_position;
	reg [DATA_BITS - 1:0] key_cache_h0 [(MAX_SEQ_LEN * HEAD_DIM) - 1:0];
	reg [DATA_BITS - 1:0] key_cache_h1 [(MAX_SEQ_LEN * HEAD_DIM) - 1:0];
	reg [DATA_BITS - 1:0] key_cache_h2 [(MAX_SEQ_LEN * HEAD_DIM) - 1:0];
	reg [DATA_BITS - 1:0] key_cache_h3 [(MAX_SEQ_LEN * HEAD_DIM) - 1:0];
	reg [DATA_BITS - 1:0] value_cache_h0 [(MAX_SEQ_LEN * HEAD_DIM) - 1:0];
	reg [DATA_BITS - 1:0] value_cache_h1 [(MAX_SEQ_LEN * HEAD_DIM) - 1:0];
	reg [DATA_BITS - 1:0] value_cache_h2 [(MAX_SEQ_LEN * HEAD_DIM) - 1:0];
	reg [DATA_BITS - 1:0] value_cache_h3 [(MAX_SEQ_LEN * HEAD_DIM) - 1:0];
	reg [$clog2(MAX_SEQ_LEN) - 1:0] window_start;
	localparam ADDR_WIDTH = $clog2(MAX_SEQ_LEN * HEAD_DIM);
	function automatic [ADDR_WIDTH - 1:0] sv2v_cast_A84C1;
		input reg [ADDR_WIDTH - 1:0] inp;
		sv2v_cast_A84C1 = inp;
	endfunction
	function automatic signed [ADDR_WIDTH - 1:0] sv2v_cast_A84C1_signed;
		input reg signed [ADDR_WIDTH - 1:0] inp;
		sv2v_cast_A84C1_signed = inp;
	endfunction
	wire [ADDR_WIDTH - 1:0] key_write_addr = (sv2v_cast_A84C1(seq_position) * sv2v_cast_A84C1_signed(HEAD_DIM)) + sv2v_cast_A84C1(key_dim_sel);
	wire [ADDR_WIDTH - 1:0] value_write_addr = (sv2v_cast_A84C1(seq_position) * sv2v_cast_A84C1_signed(HEAD_DIM)) + sv2v_cast_A84C1(value_dim_sel);
	wire [ADDR_WIDTH - 1:0] key_read_addr = (sv2v_cast_A84C1(key_read_pos) * sv2v_cast_A84C1_signed(HEAD_DIM)) + sv2v_cast_A84C1(key_read_dim);
	wire [ADDR_WIDTH - 1:0] value_read_addr = (sv2v_cast_A84C1(value_read_pos) * sv2v_cast_A84C1_signed(HEAD_DIM)) + sv2v_cast_A84C1(value_read_dim);
	reg [$clog2(MAX_SEQ_LEN) - 1:0] batch_counter;
	reg batch_in_progress;
	reg [DATA_BITS - 1:0] key_read_data;
	reg [DATA_BITS - 1:0] value_read_data;
	always @(*) begin
		key_read_data = {DATA_BITS {1'b0}};
		case (key_read_head)
			2'd0: key_read_data = key_cache_h0[key_read_addr];
			2'd1: key_read_data = key_cache_h1[key_read_addr];
			2'd2: key_read_data = key_cache_h2[key_read_addr];
			2'd3: key_read_data = key_cache_h3[key_read_addr];
		endcase
	end
	always @(*) begin
		value_read_data = {DATA_BITS {1'b0}};
		case (value_read_head)
			2'd0: value_read_data = value_cache_h0[value_read_addr];
			2'd1: value_read_data = value_cache_h1[value_read_addr];
			2'd2: value_read_data = value_cache_h2[value_read_addr];
			2'd3: value_read_data = value_cache_h3[value_read_addr];
		endcase
	end
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(posedge clk)
		if (reset || clear_cache) begin
			cache_length <= 0;
			window_start <= 0;
			oldest_position <= 0;
			cache_full <= 1'b0;
			key_data_out <= {DATA_BITS {1'b0}};
			key_valid <= 1'b0;
			value_data_out <= {DATA_BITS {1'b0}};
			value_valid <= 1'b0;
			batch_valid <= 1'b0;
			batch_done <= 1'b0;
			batch_counter <= 0;
			batch_in_progress <= 1'b0;
		end
		else if (enable) begin
			key_valid <= 1'b0;
			value_valid <= 1'b0;
			batch_done <= 1'b0;
			if (key_write_en)
				case (key_head_sel)
					2'd0: key_cache_h0[key_write_addr] <= key_data_in;
					2'd1: key_cache_h1[key_write_addr] <= key_data_in;
					2'd2: key_cache_h2[key_write_addr] <= key_data_in;
					2'd3: key_cache_h3[key_write_addr] <= key_data_in;
				endcase
			if (value_write_en) begin
				case (value_head_sel)
					2'd0: value_cache_h0[value_write_addr] <= value_data_in;
					2'd1: value_cache_h1[value_write_addr] <= value_data_in;
					2'd2: value_cache_h2[value_write_addr] <= value_data_in;
					2'd3: value_cache_h3[value_write_addr] <= value_data_in;
				endcase
				if (append_mode && (sv2v_cast_32(value_dim_sel) == (HEAD_DIM - 32'sd1))) begin
					if (sv2v_cast_32(cache_length) < MAX_SEQ_LEN)
						cache_length <= cache_length + 1;
					else begin
						cache_full <= 1'b1;
						if (sliding_window_en) begin
							window_start <= window_start + 1;
							oldest_position <= oldest_position + 1;
						end
					end
				end
			end
			if (key_read_en) begin
				key_data_out <= key_read_data;
				key_valid <= 1'b1;
			end
			if (value_read_en) begin
				value_data_out <= value_read_data;
				value_valid <= 1'b1;
			end
			if (batch_read_en && !batch_in_progress) begin
				batch_in_progress <= 1'b1;
				batch_counter <= batch_start_pos;
				batch_valid <= 1'b0;
			end
			if (batch_in_progress) begin
				batch_counter <= batch_counter + 1;
				batch_valid <= 1'b1;
				if (batch_counter >= batch_end_pos) begin
					batch_in_progress <= 1'b0;
					batch_done <= 1'b1;
					batch_valid <= 1'b0;
				end
			end
		end
endmodule
`default_nettype none
module lsu (
	clk,
	reset,
	enable,
	core_state,
	decoded_mem_read_enable,
	decoded_mem_write_enable,
	rs,
	rt,
	mem_read_valid,
	mem_read_address,
	mem_read_ready,
	mem_read_data,
	mem_write_valid,
	mem_write_address,
	mem_write_data,
	mem_write_ready,
	lsu_state,
	lsu_out
);
	parameter ADDR_BITS = 8;
	parameter DATA_BITS = 16;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [2:0] core_state;
	input wire decoded_mem_read_enable;
	input wire decoded_mem_write_enable;
	input wire [DATA_BITS - 1:0] rs;
	input wire [DATA_BITS - 1:0] rt;
	output reg mem_read_valid;
	output wire [ADDR_BITS - 1:0] mem_read_address;
	input wire mem_read_ready;
	input wire [DATA_BITS - 1:0] mem_read_data;
	output reg mem_write_valid;
	output wire [ADDR_BITS - 1:0] mem_write_address;
	output wire [DATA_BITS - 1:0] mem_write_data;
	input wire mem_write_ready;
	output reg [1:0] lsu_state;
	output reg [DATA_BITS - 1:0] lsu_out;
	localparam IDLE = 2'b00;
	localparam REQUESTING = 2'b01;
	localparam WAITING = 2'b10;
	localparam DONE = 2'b11;
	function automatic [ADDR_BITS - 1:0] sv2v_cast_5DD1B;
		input reg [ADDR_BITS - 1:0] inp;
		sv2v_cast_5DD1B = inp;
	endfunction
	assign mem_read_address = sv2v_cast_5DD1B(rs);
	assign mem_write_address = sv2v_cast_5DD1B(rs);
	assign mem_write_data = rt;
	always @(posedge clk)
		if (reset) begin
			lsu_state <= IDLE;
			lsu_out <= {DATA_BITS {1'b0}};
			mem_read_valid <= 0;
			mem_write_valid <= 0;
		end
		else if (enable) begin
			if (decoded_mem_read_enable)
				case (lsu_state)
					IDLE:
						if (core_state == 3'b011)
							lsu_state <= REQUESTING;
					REQUESTING: begin
						mem_read_valid <= 1;
						lsu_state <= WAITING;
					end
					WAITING:
						if (mem_read_ready == 1) begin
							mem_read_valid <= 0;
							lsu_out <= mem_read_data;
							lsu_state <= DONE;
						end
					DONE:
						if (core_state == 3'b110)
							lsu_state <= IDLE;
				endcase
			if (decoded_mem_write_enable)
				case (lsu_state)
					IDLE:
						if (core_state == 3'b011)
							lsu_state <= REQUESTING;
					REQUESTING: begin
						mem_write_valid <= 1;
						lsu_state <= WAITING;
					end
					WAITING:
						if (mem_write_ready) begin
							mem_write_valid <= 0;
							lsu_state <= DONE;
						end
					DONE:
						if (core_state == 3'b110)
							lsu_state <= IDLE;
				endcase
		end
endmodule
`default_nettype none
module mem_coalesce (
	clk,
	reset,
	enable,
	req_valid,
	req_address_flat,
	req_is_write,
	req_write_data_flat,
	req_ready,
	req_read_data_flat,
	coalesced_valid,
	coalesced_base_addr,
	coalesced_is_write,
	coalesced_count,
	coalesced_write_data,
	coalesced_ready,
	coalesced_read_data
);
	parameter ADDR_BITS = 8;
	parameter DATA_BITS = 16;
	parameter NUM_REQUESTS = 4;
	parameter COALESCE_WIDTH = 4;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [NUM_REQUESTS - 1:0] req_valid;
	input wire [(ADDR_BITS * NUM_REQUESTS) - 1:0] req_address_flat;
	input wire [NUM_REQUESTS - 1:0] req_is_write;
	input wire [(DATA_BITS * NUM_REQUESTS) - 1:0] req_write_data_flat;
	output reg [NUM_REQUESTS - 1:0] req_ready;
	output reg [(DATA_BITS * NUM_REQUESTS) - 1:0] req_read_data_flat;
	output reg coalesced_valid;
	output reg [ADDR_BITS - 1:0] coalesced_base_addr;
	output reg coalesced_is_write;
	output reg [$clog2(COALESCE_WIDTH):0] coalesced_count;
	output reg [(DATA_BITS * COALESCE_WIDTH) - 1:0] coalesced_write_data;
	input wire coalesced_ready;
	input wire [(DATA_BITS * COALESCE_WIDTH) - 1:0] coalesced_read_data;
	wire [ADDR_BITS - 1:0] req_address [NUM_REQUESTS - 1:0];
	wire [DATA_BITS - 1:0] req_write_data [NUM_REQUESTS - 1:0];
	reg [DATA_BITS - 1:0] req_read_data [NUM_REQUESTS - 1:0];
	genvar _gv_u_1;
	generate
		for (_gv_u_1 = 0; _gv_u_1 < NUM_REQUESTS; _gv_u_1 = _gv_u_1 + 1) begin : unflatten
			localparam u = _gv_u_1;
			assign req_address[u] = req_address_flat[((u + 1) * ADDR_BITS) - 1:u * ADDR_BITS];
			assign req_write_data[u] = req_write_data_flat[((u + 1) * DATA_BITS) - 1:u * DATA_BITS];
		end
	endgenerate
	integer fl_idx;
	always @(*)
		for (fl_idx = 0; fl_idx < NUM_REQUESTS; fl_idx = fl_idx + 1)
			req_read_data_flat[fl_idx * DATA_BITS+:DATA_BITS] = req_read_data[fl_idx];
	localparam IDLE = 3'b000;
	localparam ANALYZE = 3'b001;
	localparam COALESCE = 3'b010;
	localparam REQUEST = 3'b011;
	localparam WAIT = 3'b100;
	localparam DISTRIBUTE = 3'b101;
	reg [2:0] state;
	reg [NUM_REQUESTS - 1:0] pending_mask;
	reg [ADDR_BITS - 1:0] pending_addr [NUM_REQUESTS - 1:0];
	reg pending_is_write [NUM_REQUESTS - 1:0];
	reg [DATA_BITS - 1:0] pending_data [NUM_REQUESTS - 1:0];
	reg [ADDR_BITS - 1:0] base_address;
	reg [NUM_REQUESTS - 1:0] coalesce_mask;
	reg [$clog2(COALESCE_WIDTH):0] num_coalesced;
	reg coalesce_is_write;
	wire [ADDR_BITS - 1:0] min_addr;
	wire [NUM_REQUESTS - 1:0] sequential_mask;
	integer j;
	reg [ADDR_BITS - 1:0] temp_min;
	always @(*) begin
		temp_min = {ADDR_BITS {1'b1}};
		for (j = 0; j < NUM_REQUESTS; j = j + 1)
			if (pending_mask[j] && (pending_addr[j] < temp_min))
				temp_min = pending_addr[j];
	end
	assign min_addr = temp_min;
	genvar _gv_g_2;
	generate
		for (_gv_g_2 = 0; _gv_g_2 < NUM_REQUESTS; _gv_g_2 = _gv_g_2 + 1) begin : seq_check
			localparam g = _gv_g_2;
			assign sequential_mask[g] = (pending_mask[g] && (pending_addr[g] >= base_address)) && (pending_addr[g] < (base_address + COALESCE_WIDTH));
		end
	endgenerate
	integer k;
	reg [$clog2(COALESCE_WIDTH):0] count_ones;
	always @(*) begin
		count_ones = 0;
		for (k = 0; k < NUM_REQUESTS; k = k + 1)
			if (coalesce_mask[k])
				count_ones = count_ones + 1;
	end
	integer m;
	always @(posedge clk)
		if (reset) begin
			state <= IDLE;
			pending_mask <= {NUM_REQUESTS {1'b0}};
			coalesce_mask <= {NUM_REQUESTS {1'b0}};
			req_ready <= {NUM_REQUESTS {1'b0}};
			coalesced_valid <= 1'b0;
			coalesced_base_addr <= {ADDR_BITS {1'b0}};
			coalesced_is_write <= 1'b0;
			coalesced_count <= 0;
			coalesced_write_data <= {DATA_BITS * COALESCE_WIDTH {1'b0}};
			num_coalesced <= 0;
			base_address <= {ADDR_BITS {1'b0}};
			coalesce_is_write <= 1'b0;
			for (m = 0; m < NUM_REQUESTS; m = m + 1)
				begin
					pending_addr[m] <= {ADDR_BITS {1'b0}};
					pending_is_write[m] <= 1'b0;
					pending_data[m] <= {DATA_BITS {1'b0}};
					req_read_data[m] <= {DATA_BITS {1'b0}};
				end
		end
		else if (enable)
			case (state)
				IDLE: begin
					req_ready <= {NUM_REQUESTS {1'b0}};
					coalesced_valid <= 1'b0;
					if (|req_valid) begin
						pending_mask <= req_valid;
						for (m = 0; m < NUM_REQUESTS; m = m + 1)
							if (req_valid[m]) begin
								pending_addr[m] <= req_address[m];
								pending_is_write[m] <= req_is_write[m];
								pending_data[m] <= req_write_data[m];
							end
						state <= ANALYZE;
					end
				end
				ANALYZE: begin
					base_address <= min_addr;
					coalesce_is_write <= pending_is_write[0];
					state <= COALESCE;
				end
				COALESCE: begin
					coalesce_mask <= {NUM_REQUESTS {1'b0}};
					for (m = 0; m < NUM_REQUESTS; m = m + 1)
						if (sequential_mask[m] && (pending_is_write[m] == coalesce_is_write))
							coalesce_mask[m] <= 1'b1;
					num_coalesced <= count_ones;
					state <= REQUEST;
				end
				REQUEST: begin
					coalesced_valid <= 1'b1;
					coalesced_base_addr <= base_address;
					coalesced_is_write <= coalesce_is_write;
					coalesced_count <= num_coalesced;
					if (coalesce_is_write) begin
						for (m = 0; m < NUM_REQUESTS; m = m + 1)
							if (coalesce_mask[m])
								coalesced_write_data[(pending_addr[m] - base_address) * DATA_BITS+:DATA_BITS] <= pending_data[m];
					end
					state <= WAIT;
				end
				WAIT:
					if (coalesced_ready) begin
						coalesced_valid <= 1'b0;
						state <= DISTRIBUTE;
					end
				DISTRIBUTE: begin
					for (m = 0; m < NUM_REQUESTS; m = m + 1)
						if (coalesce_mask[m]) begin
							req_ready[m] <= 1'b1;
							if (!coalesce_is_write)
								req_read_data[m] <= coalesced_read_data[(pending_addr[m] - base_address) * DATA_BITS+:DATA_BITS];
							pending_mask[m] <= 1'b0;
						end
					if (|(pending_mask & ~coalesce_mask))
						state <= ANALYZE;
					else
						state <= IDLE;
				end
				default: state <= IDLE;
			endcase
endmodule
`default_nettype none
module pc (
	clk,
	reset,
	enable,
	core_state,
	decoded_nzp,
	decoded_nzp_write_enable,
	decoded_pc_mux,
	alu_out,
	current_pc,
	next_pc,
	branch_taken,
	instruction
);
	parameter DATA_MEM_DATA_BITS = 16;
	parameter PROGRAM_MEM_ADDR_BITS = 8;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [2:0] core_state;
	input wire [2:0] decoded_nzp;
	input wire decoded_nzp_write_enable;
	input wire decoded_pc_mux;
	input wire [2:0] alu_out;
	input wire [PROGRAM_MEM_ADDR_BITS - 1:0] current_pc;
	output wire [PROGRAM_MEM_ADDR_BITS - 1:0] next_pc;
	output wire branch_taken;
	input wire [8:0] instruction;
	reg [2:0] nzp;
	assign branch_taken = (enable && decoded_pc_mux) && ((nzp & decoded_nzp) != 3'b000);
	wire signed [PROGRAM_MEM_ADDR_BITS:0] pc_plus_one_s = $signed({1'b0, current_pc}) + $signed({{PROGRAM_MEM_ADDR_BITS {1'b0}}, 1'b1});
	localparam integer BR_OFF_W = PROGRAM_MEM_ADDR_BITS + 1;
	wire signed [BR_OFF_W - 1:0] br_off9_s = $signed({{BR_OFF_W - 9 {instruction[8]}}, instruction[8:0]});
	wire signed [PROGRAM_MEM_ADDR_BITS:0] br_target_s = pc_plus_one_s + br_off9_s;
	function automatic signed [PROGRAM_MEM_ADDR_BITS - 1:0] sv2v_cast_A4893_signed;
		input reg signed [PROGRAM_MEM_ADDR_BITS - 1:0] inp;
		sv2v_cast_A4893_signed = inp;
	endfunction
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] br_target = sv2v_cast_A4893_signed(br_target_s);
	assign next_pc = (decoded_pc_mux && ((nzp & decoded_nzp) != 3'b000) ? br_target : current_pc + 1'b1);
	always @(posedge clk)
		if (reset)
			nzp <= 3'b000;
		else if (enable) begin
			if (core_state == 3'b110) begin
				if (decoded_nzp_write_enable)
					nzp <= alu_out;
			end
		end
endmodule
`default_nettype none
module registers (
	clk,
	reset,
	enable,
	block_id,
	core_state,
	decoded_rd_address,
	decoded_rs_address,
	decoded_rt_address,
	write_rd_address,
	decoded_reg_write_enable,
	decoded_reg_input_mux,
	decoded_immediate,
	alu_out,
	lsu_out,
	fma_out,
	act_out,
	systolic_out,
	rs,
	rt,
	rd_data
);
	parameter THREADS_PER_BLOCK = 4;
	parameter THREAD_ID = 0;
	parameter DATA_BITS = 16;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [7:0] block_id;
	input wire [2:0] core_state;
	input wire [3:0] decoded_rd_address;
	input wire [3:0] decoded_rs_address;
	input wire [3:0] decoded_rt_address;
	input wire [3:0] write_rd_address;
	input wire decoded_reg_write_enable;
	input wire [2:0] decoded_reg_input_mux;
	input wire [7:0] decoded_immediate;
	input wire [DATA_BITS - 1:0] alu_out;
	input wire [DATA_BITS - 1:0] lsu_out;
	input wire [DATA_BITS - 1:0] fma_out;
	input wire [DATA_BITS - 1:0] act_out;
	input wire [DATA_BITS - 1:0] systolic_out;
	output wire [DATA_BITS - 1:0] rs;
	output wire [DATA_BITS - 1:0] rt;
	output wire [DATA_BITS - 1:0] rd_data;
	localparam [2:0] MUX_ALU = 3'b000;
	localparam [2:0] MUX_MEMORY = 3'b001;
	localparam [2:0] MUX_CONSTANT = 3'b010;
	localparam [2:0] MUX_FMA = 3'b011;
	localparam [2:0] MUX_ACT = 3'b100;
	localparam [2:0] MUX_SYSTOLIC = 3'b101;
	reg [DATA_BITS - 1:0] registers [12:0];
	wire [DATA_BITS - 1:0] rs_raw = (decoded_rs_address < 13 ? registers[decoded_rs_address] : {DATA_BITS {1'b0}});
	wire [DATA_BITS - 1:0] rt_raw = (decoded_rt_address < 13 ? registers[decoded_rt_address] : {DATA_BITS {1'b0}});
	wire [DATA_BITS - 1:0] rd_data_raw = (decoded_rd_address < 13 ? registers[decoded_rd_address] : {DATA_BITS {1'b0}});
	assign rs = (decoded_rs_address == 13 ? {{DATA_BITS - 8 {1'b0}}, block_id} : (decoded_rs_address == 14 ? {{DATA_BITS - 8 {1'b0}}, THREADS_PER_BLOCK[7:0]} : (decoded_rs_address == 15 ? {{DATA_BITS - 8 {1'b0}}, THREAD_ID[7:0]} : rs_raw)));
	assign rt = (decoded_rt_address == 13 ? {{DATA_BITS - 8 {1'b0}}, block_id} : (decoded_rt_address == 14 ? {{DATA_BITS - 8 {1'b0}}, THREADS_PER_BLOCK[7:0]} : (decoded_rt_address == 15 ? {{DATA_BITS - 8 {1'b0}}, THREAD_ID[7:0]} : rt_raw)));
	assign rd_data = (decoded_rd_address == 13 ? {{DATA_BITS - 8 {1'b0}}, block_id} : (decoded_rd_address == 14 ? {{DATA_BITS - 8 {1'b0}}, THREADS_PER_BLOCK[7:0]} : (decoded_rd_address == 15 ? {{DATA_BITS - 8 {1'b0}}, THREAD_ID[7:0]} : rd_data_raw)));
	wire [DATA_BITS - 1:0] immediate_extended;
	assign immediate_extended = {{8 {decoded_immediate[7]}}, decoded_immediate};
	reg [DATA_BITS - 1:0] write_data;
	always @(*)
		case (decoded_reg_input_mux)
			MUX_ALU: write_data = alu_out;
			MUX_MEMORY: write_data = lsu_out;
			MUX_CONSTANT: write_data = immediate_extended;
			MUX_FMA: write_data = fma_out;
			MUX_ACT: write_data = act_out;
			MUX_SYSTOLIC: write_data = systolic_out;
			default: write_data = alu_out;
		endcase
	always @(posedge clk)
		if (reset) begin
			registers[0] <= {DATA_BITS {1'b0}};
			registers[1] <= {DATA_BITS {1'b0}};
			registers[2] <= {DATA_BITS {1'b0}};
			registers[3] <= {DATA_BITS {1'b0}};
			registers[4] <= {DATA_BITS {1'b0}};
			registers[5] <= {DATA_BITS {1'b0}};
			registers[6] <= {DATA_BITS {1'b0}};
			registers[7] <= {DATA_BITS {1'b0}};
			registers[8] <= {DATA_BITS {1'b0}};
			registers[9] <= {DATA_BITS {1'b0}};
			registers[10] <= {DATA_BITS {1'b0}};
			registers[11] <= {DATA_BITS {1'b0}};
			registers[12] <= {DATA_BITS {1'b0}};
		end
		else if (enable) begin
			if (core_state == 3'b110) begin
				if (decoded_reg_write_enable && (write_rd_address < 13))
					registers[write_rd_address] <= write_data;
			end
		end
endmodule
`default_nettype none
module scheduler (
	clk,
	reset,
	start,
	decoded_fma_enable,
	decoded_ret,
	decoded_branch,
	branch_taken,
	branch_target,
	reconverge_pc,
	fetcher_state,
	lsu_state_flat,
	current_pc,
	next_pc_flat,
	active_mask,
	diverged,
	core_state,
	done
);
	parameter THREADS_PER_BLOCK = 4;
	parameter PROGRAM_MEM_ADDR_BITS = 8;
	input wire clk;
	input wire reset;
	input wire start;
	input wire decoded_fma_enable;
	input wire decoded_ret;
	input wire decoded_branch;
	input wire [THREADS_PER_BLOCK - 1:0] branch_taken;
	input wire [PROGRAM_MEM_ADDR_BITS - 1:0] branch_target;
	input wire [PROGRAM_MEM_ADDR_BITS - 1:0] reconverge_pc;
	input wire [2:0] fetcher_state;
	input wire [(2 * THREADS_PER_BLOCK) - 1:0] lsu_state_flat;
	output reg [PROGRAM_MEM_ADDR_BITS - 1:0] current_pc;
	input wire [(PROGRAM_MEM_ADDR_BITS * THREADS_PER_BLOCK) - 1:0] next_pc_flat;
	output wire [THREADS_PER_BLOCK - 1:0] active_mask;
	output wire diverged;
	output reg [2:0] core_state;
	output reg done;
	wire [1:0] lsu_state [THREADS_PER_BLOCK - 1:0];
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] next_pc [THREADS_PER_BLOCK - 1:0];
	genvar _gv_sch_idx_1;
	generate
		for (_gv_sch_idx_1 = 0; _gv_sch_idx_1 < THREADS_PER_BLOCK; _gv_sch_idx_1 = _gv_sch_idx_1 + 1) begin : unflatten_sch
			localparam sch_idx = _gv_sch_idx_1;
			assign lsu_state[sch_idx] = lsu_state_flat[((sch_idx + 1) * 2) - 1:sch_idx * 2];
			assign next_pc[sch_idx] = next_pc_flat[((sch_idx + 1) * PROGRAM_MEM_ADDR_BITS) - 1:sch_idx * PROGRAM_MEM_ADDR_BITS];
		end
	endgenerate
	localparam IDLE = 3'b000;
	localparam FETCH = 3'b001;
	localparam DECODE = 3'b010;
	localparam REQUEST = 3'b011;
	localparam WAIT = 3'b100;
	localparam EXECUTE = 3'b101;
	localparam UPDATE = 3'b110;
	localparam DONE = 3'b111;
	reg any_lsu_waiting;
	integer i;
	reg fma_execute_second_cycle;
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] diverge_next_pc;
	wire diverge_stall;
	branch_diverge #(
		.THREADS_PER_WARP(THREADS_PER_BLOCK),
		.STACK_DEPTH(2),
		.PC_BITS(PROGRAM_MEM_ADDR_BITS)
	) branch_diverge_inst(
		.clk(clk),
		.reset(reset),
		.enable(1'b1),
		.branch_instruction(decoded_branch),
		.branch_taken(branch_taken),
		.branch_target(branch_target),
		.fallthrough_pc(current_pc + 1'b1),
		.reconverge_pc(reconverge_pc),
		.current_pc(current_pc),
		.active_mask(active_mask),
		.next_pc(diverge_next_pc),
		.diverged(diverged),
		.stall(diverge_stall)
	);
	always @(*) begin
		any_lsu_waiting = 1'b0;
		for (i = 0; i < THREADS_PER_BLOCK; i = i + 1)
			if ((lsu_state[i] == 2'b01) || (lsu_state[i] == 2'b10))
				any_lsu_waiting = 1'b1;
	end
	always @(posedge clk)
		if (reset) begin
			current_pc <= 0;
			core_state <= IDLE;
			done <= 0;
			fma_execute_second_cycle <= 1'b0;
		end
		else
			case (core_state)
				IDLE:
					if (start) begin
						core_state <= FETCH;
						fma_execute_second_cycle <= 1'b0;
					end
				FETCH:
					if (fetcher_state == 3'b010)
						core_state <= DECODE;
				DECODE: core_state <= REQUEST;
				REQUEST: core_state <= WAIT;
				WAIT:
					if (!any_lsu_waiting) begin
						core_state <= EXECUTE;
						fma_execute_second_cycle <= 1'b0;
					end
				EXECUTE:
					if (decoded_fma_enable && !fma_execute_second_cycle) begin
						fma_execute_second_cycle <= 1'b1;
						core_state <= EXECUTE;
					end
					else begin
						fma_execute_second_cycle <= 1'b0;
						core_state <= UPDATE;
					end
				UPDATE:
					if (decoded_ret) begin
						done <= 1;
						core_state <= DONE;
					end
					else if (diverge_stall)
						core_state <= UPDATE;
					else begin
						current_pc <= (diverged ? diverge_next_pc : next_pc[THREADS_PER_BLOCK - 1]);
						core_state <= FETCH;
					end
				DONE:
					;
			endcase
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
module weight_mem (
	clk,
	reset,
	enable,
	weight_read_en,
	weight_bank_sel,
	weight_addr,
	weight_data_out,
	weight_valid,
	weight_write_en,
	weight_write_bank,
	weight_write_addr,
	weight_write_data,
	act_read_en,
	act_write_en,
	act_bank_sel,
	act_addr,
	act_data_in,
	act_data_out,
	act_valid,
	swap_buffers,
	prefetch_en,
	prefetch_start_addr,
	prefetch_length,
	prefetch_done,
	bank_busy
);
	parameter DATA_BITS = 16;
	parameter NUM_BANKS = 4;
	parameter BANK_DEPTH = 1024;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire weight_read_en;
	input wire [$clog2(NUM_BANKS) - 1:0] weight_bank_sel;
	input wire [$clog2(BANK_DEPTH) - 1:0] weight_addr;
	output reg [DATA_BITS - 1:0] weight_data_out;
	output reg weight_valid;
	input wire weight_write_en;
	input wire [$clog2(NUM_BANKS) - 1:0] weight_write_bank;
	input wire [$clog2(BANK_DEPTH) - 1:0] weight_write_addr;
	input wire [DATA_BITS - 1:0] weight_write_data;
	input wire act_read_en;
	input wire act_write_en;
	input wire [$clog2(NUM_BANKS) - 1:0] act_bank_sel;
	input wire [$clog2(BANK_DEPTH) - 1:0] act_addr;
	input wire [DATA_BITS - 1:0] act_data_in;
	output reg [DATA_BITS - 1:0] act_data_out;
	output reg act_valid;
	input wire swap_buffers;
	input wire prefetch_en;
	input wire [$clog2(BANK_DEPTH) - 1:0] prefetch_start_addr;
	input wire [$clog2(BANK_DEPTH) - 1:0] prefetch_length;
	output reg prefetch_done;
	output reg [NUM_BANKS - 1:0] bank_busy;
	reg [DATA_BITS - 1:0] weight_bank_0_buf0 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] weight_bank_0_buf1 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] weight_bank_1_buf0 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] weight_bank_1_buf1 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] weight_bank_2_buf0 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] weight_bank_2_buf1 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] weight_bank_3_buf0 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] weight_bank_3_buf1 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] act_bank_0_buf0 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] act_bank_0_buf1 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] act_bank_1_buf0 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] act_bank_1_buf1 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] act_bank_2_buf0 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] act_bank_2_buf1 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] act_bank_3_buf0 [BANK_DEPTH - 1:0];
	reg [DATA_BITS - 1:0] act_bank_3_buf1 [BANK_DEPTH - 1:0];
	reg active_buffer;
	reg prefetching;
	reg [$clog2(BANK_DEPTH) - 1:0] prefetch_counter;
	reg [$clog2(BANK_DEPTH) - 1:0] prefetch_end;
	reg [DATA_BITS - 1:0] weight_read_data;
	reg [DATA_BITS - 1:0] act_read_data;
	always @(*) begin
		weight_read_data = {DATA_BITS {1'b0}};
		if (weight_read_en)
			case (weight_bank_sel)
				2'd0: weight_read_data = (active_buffer ? weight_bank_0_buf1[weight_addr] : weight_bank_0_buf0[weight_addr]);
				2'd1: weight_read_data = (active_buffer ? weight_bank_1_buf1[weight_addr] : weight_bank_1_buf0[weight_addr]);
				2'd2: weight_read_data = (active_buffer ? weight_bank_2_buf1[weight_addr] : weight_bank_2_buf0[weight_addr]);
				2'd3: weight_read_data = (active_buffer ? weight_bank_3_buf1[weight_addr] : weight_bank_3_buf0[weight_addr]);
			endcase
	end
	always @(*) begin
		act_read_data = {DATA_BITS {1'b0}};
		if (act_read_en)
			case (act_bank_sel)
				2'd0: act_read_data = (active_buffer ? act_bank_0_buf1[act_addr] : act_bank_0_buf0[act_addr]);
				2'd1: act_read_data = (active_buffer ? act_bank_1_buf1[act_addr] : act_bank_1_buf0[act_addr]);
				2'd2: act_read_data = (active_buffer ? act_bank_2_buf1[act_addr] : act_bank_2_buf0[act_addr]);
				2'd3: act_read_data = (active_buffer ? act_bank_3_buf1[act_addr] : act_bank_3_buf0[act_addr]);
			endcase
	end
	always @(posedge clk)
		if (reset) begin
			weight_data_out <= {DATA_BITS {1'b0}};
			weight_valid <= 1'b0;
			act_data_out <= {DATA_BITS {1'b0}};
			act_valid <= 1'b0;
			active_buffer <= 1'b0;
			prefetching <= 1'b0;
			prefetch_done <= 1'b0;
			prefetch_counter <= 0;
			prefetch_end <= 0;
			bank_busy <= {NUM_BANKS {1'b0}};
		end
		else if (enable) begin
			weight_valid <= 1'b0;
			act_valid <= 1'b0;
			prefetch_done <= 1'b0;
			if (swap_buffers)
				active_buffer <= ~active_buffer;
			if (weight_read_en) begin
				weight_data_out <= weight_read_data;
				weight_valid <= 1'b1;
			end
			if (weight_write_en)
				case (weight_write_bank)
					2'd0:
						if (active_buffer)
							weight_bank_0_buf0[weight_write_addr] <= weight_write_data;
						else
							weight_bank_0_buf1[weight_write_addr] <= weight_write_data;
					2'd1:
						if (active_buffer)
							weight_bank_1_buf0[weight_write_addr] <= weight_write_data;
						else
							weight_bank_1_buf1[weight_write_addr] <= weight_write_data;
					2'd2:
						if (active_buffer)
							weight_bank_2_buf0[weight_write_addr] <= weight_write_data;
						else
							weight_bank_2_buf1[weight_write_addr] <= weight_write_data;
					2'd3:
						if (active_buffer)
							weight_bank_3_buf0[weight_write_addr] <= weight_write_data;
						else
							weight_bank_3_buf1[weight_write_addr] <= weight_write_data;
				endcase
			if (act_read_en) begin
				act_data_out <= act_read_data;
				act_valid <= 1'b1;
			end
			if (act_write_en)
				case (act_bank_sel)
					2'd0:
						if (active_buffer)
							act_bank_0_buf1[act_addr] <= act_data_in;
						else
							act_bank_0_buf0[act_addr] <= act_data_in;
					2'd1:
						if (active_buffer)
							act_bank_1_buf1[act_addr] <= act_data_in;
						else
							act_bank_1_buf0[act_addr] <= act_data_in;
					2'd2:
						if (active_buffer)
							act_bank_2_buf1[act_addr] <= act_data_in;
						else
							act_bank_2_buf0[act_addr] <= act_data_in;
					2'd3:
						if (active_buffer)
							act_bank_3_buf1[act_addr] <= act_data_in;
						else
							act_bank_3_buf0[act_addr] <= act_data_in;
				endcase
			if (prefetch_en && !prefetching) begin
				prefetching <= 1'b1;
				prefetch_counter <= prefetch_start_addr;
				prefetch_end <= prefetch_start_addr + prefetch_length;
				bank_busy <= {NUM_BANKS {1'b1}};
			end
			if (prefetching) begin
				prefetch_counter <= prefetch_counter + 1;
				if (prefetch_counter >= (prefetch_end - 1)) begin
					prefetching <= 1'b0;
					prefetch_done <= 1'b1;
					bank_busy <= {NUM_BANKS {1'b0}};
				end
			end
		end
endmodule