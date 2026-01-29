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
	localparam [DATA_BITS - 1:0] Q115_MIN = 16'h8000;
	localparam [DATA_BITS - 1:0] Q115_LEAKY_ALPHA = 16'h0148;
	localparam [1:0] ACT_NONE = 2'b00;
	localparam [1:0] ACT_RELU = 2'b01;
	localparam [1:0] ACT_LEAKY_RELU = 2'b10;
	localparam [1:0] ACT_CLIPPED_RELU = 2'b11;
	reg [DATA_BITS - 1:0] activation_out_reg;
	assign activation_out = activation_out_reg;
	wire signed [16:0] biased_sum = $signed({unbiased_activation[15], unbiased_activation}) + $signed({bias[15], bias});
	wire overflow_pos = ((~biased_sum[16] & biased_sum[15]) & ~unbiased_activation[15]) & ~bias[15];
	wire overflow_neg = ((biased_sum[16] & ~biased_sum[15]) & unbiased_activation[15]) & bias[15];
	wire [DATA_BITS - 1:0] biased_activation = (overflow_pos ? Q115_MAX : (overflow_neg ? Q115_MIN : biased_sum[DATA_BITS - 1:0]));
	wire is_negative = biased_activation[15];
	wire signed [DATA_BITS - 1:0] leaky_value = $signed(biased_activation) >>> 7;
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
						MUL: alu_out_reg <= rs * rt;
						DIV: alu_out_reg <= (rt != 0 ? rs / rt : {DATA_BITS {1'b0}});
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
	reg [((THREADS_PER_WARP + PC_BITS) + PC_BITS) + 0:0] diverge_stack [STACK_DEPTH - 1:0];
	reg [$clog2(STACK_DEPTH) - 1:0] stack_ptr;
	reg [THREADS_PER_WARP - 1:0] full_mask;
	reg executing_taken;
	wire at_reconverge = diverge_stack[(stack_ptr > 0 ? stack_ptr - 1 : 0)][0] && (current_pc == diverge_stack[(stack_ptr > 0 ? stack_ptr - 1 : 0)][PC_BITS + (PC_BITS + 0)-:((PC_BITS + (PC_BITS + 0)) >= (PC_BITS + 1) ? ((PC_BITS + (PC_BITS + 0)) - (PC_BITS + 1)) + 1 : ((PC_BITS + 1) - (PC_BITS + (PC_BITS + 0))) + 1)]);
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
	wire none_take = branch_instruction && (taken_count == 0);
	integer j;
	always @(posedge clk)
		if (reset) begin
			active_mask <= {THREADS_PER_WARP {1'b1}};
			full_mask <= {THREADS_PER_WARP {1'b1}};
			stack_ptr <= 0;
			diverged <= 1'b0;
			stall <= 1'b0;
			next_pc <= {PC_BITS {1'b0}};
			executing_taken <= 1'b0;
			for (j = 0; j < STACK_DEPTH; j = j + 1)
				begin
					diverge_stack[j][THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))-:((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) >= (PC_BITS + (PC_BITS + 1)) ? ((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) - (PC_BITS + (PC_BITS + 1))) + 1 : ((PC_BITS + (PC_BITS + 1)) - (THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0)))) + 1)] <= {THREADS_PER_WARP {1'b0}};
					diverge_stack[j][PC_BITS + (PC_BITS + 0)-:((PC_BITS + (PC_BITS + 0)) >= (PC_BITS + 1) ? ((PC_BITS + (PC_BITS + 0)) - (PC_BITS + 1)) + 1 : ((PC_BITS + 1) - (PC_BITS + (PC_BITS + 0))) + 1)] <= {PC_BITS {1'b0}};
					diverge_stack[j][PC_BITS + 0-:((PC_BITS + 0) >= 1 ? PC_BITS + 0 : 2 - (PC_BITS + 0))] <= {PC_BITS {1'b0}};
					diverge_stack[j][0] <= 1'b0;
				end
		end
		else if (enable) begin
			stall <= 1'b0;
			if (at_reconverge && (stack_ptr > 0)) begin
				stack_ptr <= stack_ptr - 1;
				if (diverge_stack[stack_ptr - 1][THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))-:((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) >= (PC_BITS + (PC_BITS + 1)) ? ((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) - (PC_BITS + (PC_BITS + 1))) + 1 : ((PC_BITS + (PC_BITS + 1)) - (THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0)))) + 1)] != {THREADS_PER_WARP {1'b0}}) begin
					active_mask <= diverge_stack[stack_ptr - 1][THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))-:((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) >= (PC_BITS + (PC_BITS + 1)) ? ((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) - (PC_BITS + (PC_BITS + 1))) + 1 : ((PC_BITS + (PC_BITS + 1)) - (THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0)))) + 1)];
					next_pc <= diverge_stack[stack_ptr - 1][PC_BITS + 0-:((PC_BITS + 0) >= 1 ? PC_BITS + 0 : 2 - (PC_BITS + 0))];
					diverge_stack[stack_ptr - 1][THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))-:((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) >= (PC_BITS + (PC_BITS + 1)) ? ((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) - (PC_BITS + (PC_BITS + 1))) + 1 : ((PC_BITS + (PC_BITS + 1)) - (THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0)))) + 1)] <= {THREADS_PER_WARP {1'b0}};
					stall <= 1'b1;
				end
				else begin
					active_mask <= full_mask;
					diverged <= stack_ptr > 1;
				end
			end
			else if (branch_instruction) begin
				if (will_diverge) begin
					if (stack_ptr < STACK_DEPTH) begin
						diverge_stack[stack_ptr][THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))-:((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) >= (PC_BITS + (PC_BITS + 1)) ? ((THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0))) - (PC_BITS + (PC_BITS + 1))) + 1 : ((PC_BITS + (PC_BITS + 1)) - (THREADS_PER_WARP + (PC_BITS + (PC_BITS + 0)))) + 1)] <= active_mask & ~branch_taken;
						diverge_stack[stack_ptr][PC_BITS + (PC_BITS + 0)-:((PC_BITS + (PC_BITS + 0)) >= (PC_BITS + 1) ? ((PC_BITS + (PC_BITS + 0)) - (PC_BITS + 1)) + 1 : ((PC_BITS + 1) - (PC_BITS + (PC_BITS + 0))) + 1)] <= reconverge_pc;
						diverge_stack[stack_ptr][PC_BITS + 0-:((PC_BITS + 0) >= 1 ? PC_BITS + 0 : 2 - (PC_BITS + 0))] <= fallthrough_pc;
						diverge_stack[stack_ptr][0] <= 1'b1;
						stack_ptr <= stack_ptr + 1;
						active_mask <= active_mask & branch_taken;
						next_pc <= branch_target;
						diverged <= 1'b1;
						executing_taken <= 1'b1;
						stall <= 1'b1;
					end
				end
				else if (all_take)
					next_pc <= branch_target;
				else
					next_pc <= fallthrough_pc;
			end
		end
	wire [$clog2(STACK_DEPTH) - 1:0] debug_stack_depth = stack_ptr;
	wire [THREADS_PER_WARP - 1:0] debug_active = active_mask;
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
	parameter LINE_SIZE = 1;
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
	reg [15:0] hit_count;
	reg [15:0] miss_count;
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
			hit_count <= 16'b0000000000000000;
			miss_count <= 16'b0000000000000000;
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
						hit_count <= hit_count + 1'b1;
					end
					else begin
						mem_read_valid <= 1'b1;
						mem_read_address <= pending_address;
						cache_state <= FETCH;
						miss_count <= miss_count + 1'b1;
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
module compute_unit (
	clk,
	reset,
	enable,
	block_id,
	core_state,
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
	current_pc,
	mem_read_valid,
	mem_read_address,
	mem_read_ready,
	mem_read_data,
	mem_write_valid,
	mem_write_address,
	mem_write_data,
	mem_write_ready,
	next_pc,
	lsu_state
);
	parameter DATA_MEM_ADDR_BITS = 12;
	parameter DATA_MEM_DATA_BITS = 16;
	parameter PROGRAM_MEM_ADDR_BITS = 12;
	parameter THREADS_PER_BLOCK = 4;
	parameter THREAD_ID = 0;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [7:0] block_id;
	input wire [2:0] core_state;
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
	input wire [7:0] current_pc;
	output reg mem_read_valid;
	output reg [DATA_MEM_ADDR_BITS - 1:0] mem_read_address;
	input wire mem_read_ready;
	input wire [DATA_MEM_DATA_BITS - 1:0] mem_read_data;
	output reg mem_write_valid;
	output reg [DATA_MEM_ADDR_BITS - 1:0] mem_write_address;
	output reg [DATA_MEM_DATA_BITS - 1:0] mem_write_data;
	input wire mem_write_ready;
	output wire [7:0] next_pc;
	output reg [1:0] lsu_state;
	wire [DATA_MEM_DATA_BITS - 1:0] rs;
	wire [DATA_MEM_DATA_BITS - 1:0] rt;
	wire [DATA_MEM_DATA_BITS - 1:0] lsu_out;
	wire [DATA_MEM_DATA_BITS - 1:0] alu_out;
	wire [DATA_MEM_DATA_BITS - 1:0] fma_out;
	wire [DATA_MEM_DATA_BITS - 1:0] act_out;
	wire [DATA_MEM_DATA_BITS - 1:0] rd_data;
	alu #(.DATA_BITS(DATA_MEM_DATA_BITS)) alu_inst(
		.clk(clk),
		.reset(reset),
		.enable(enable),
		.core_state(core_state),
		.decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
		.decoded_alu_output_mux(decoded_alu_output_mux),
		.rs(rs),
		.rt(rt),
		.alu_out(alu_out)
	);
	fma #(.DATA_BITS(DATA_MEM_DATA_BITS)) fma_inst(
		.clk(clk),
		.reset(reset),
		.enable(enable),
		.core_state(core_state),
		.decoded_fma_enable(decoded_fma_enable),
		.rs(rs),
		.rt(rt),
		.rq(rd_data),
		.fma_out(fma_out)
	);
	activation #(.DATA_BITS(DATA_MEM_DATA_BITS)) activation_inst(
		.clk(clk),
		.reset(reset),
		.enable(enable),
		.core_state(core_state),
		.activation_enable(decoded_act_enable),
		.activation_func(decoded_act_func),
		.unbiased_activation(rs),
		.bias(rt),
		.activation_out(act_out)
	);
	wire [1:1] sv2v_tmp_lsu_inst_mem_read_valid;
	always @(*) mem_read_valid = sv2v_tmp_lsu_inst_mem_read_valid;
	wire [DATA_MEM_ADDR_BITS:1] sv2v_tmp_lsu_inst_mem_read_address;
	always @(*) mem_read_address = sv2v_tmp_lsu_inst_mem_read_address;
	wire [1:1] sv2v_tmp_lsu_inst_mem_write_valid;
	always @(*) mem_write_valid = sv2v_tmp_lsu_inst_mem_write_valid;
	wire [DATA_MEM_ADDR_BITS:1] sv2v_tmp_lsu_inst_mem_write_address;
	always @(*) mem_write_address = sv2v_tmp_lsu_inst_mem_write_address;
	wire [DATA_MEM_DATA_BITS:1] sv2v_tmp_lsu_inst_mem_write_data;
	always @(*) mem_write_data = sv2v_tmp_lsu_inst_mem_write_data;
	wire [2:1] sv2v_tmp_lsu_inst_lsu_state;
	always @(*) lsu_state = sv2v_tmp_lsu_inst_lsu_state;
	lsu #(
		.ADDR_BITS(DATA_MEM_ADDR_BITS),
		.DATA_BITS(DATA_MEM_DATA_BITS)
	) lsu_inst(
		.clk(clk),
		.reset(reset),
		.enable(enable),
		.core_state(core_state),
		.decoded_mem_read_enable(decoded_mem_read_enable),
		.decoded_mem_write_enable(decoded_mem_write_enable),
		.mem_read_valid(sv2v_tmp_lsu_inst_mem_read_valid),
		.mem_read_address(sv2v_tmp_lsu_inst_mem_read_address),
		.mem_read_ready(mem_read_ready),
		.mem_read_data(mem_read_data),
		.mem_write_valid(sv2v_tmp_lsu_inst_mem_write_valid),
		.mem_write_address(sv2v_tmp_lsu_inst_mem_write_address),
		.mem_write_data(sv2v_tmp_lsu_inst_mem_write_data),
		.mem_write_ready(mem_write_ready),
		.rs(rs),
		.rt(rt),
		.lsu_state(sv2v_tmp_lsu_inst_lsu_state),
		.lsu_out(lsu_out)
	);
	registers #(
		.THREADS_PER_BLOCK(THREADS_PER_BLOCK),
		.THREAD_ID(THREAD_ID),
		.DATA_BITS(DATA_MEM_DATA_BITS)
	) register_inst(
		.clk(clk),
		.reset(reset),
		.enable(enable),
		.block_id(block_id),
		.core_state(core_state),
		.decoded_reg_write_enable(decoded_reg_write_enable),
		.decoded_reg_input_mux(decoded_reg_input_mux),
		.decoded_rd_address(decoded_rd_address),
		.decoded_rs_address(decoded_rs_address),
		.decoded_rt_address(decoded_rt_address),
		.decoded_immediate(decoded_immediate),
		.alu_out(alu_out),
		.lsu_out(lsu_out),
		.fma_out(fma_out),
		.act_out(act_out),
		.rs(rs),
		.rt(rt),
		.rd_data(rd_data)
	);
	pc #(
		.DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
		.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
	) pc_inst(
		.clk(clk),
		.reset(reset),
		.enable(enable),
		.core_state(core_state),
		.decoded_nzp(decoded_nzp),
		.decoded_immediate(decoded_immediate),
		.decoded_nzp_write_enable(decoded_nzp_write_enable),
		.decoded_pc_mux(decoded_pc_mux),
		.alu_out(alu_out),
		.current_pc(current_pc),
		.next_pc(next_pc),
		.instruction(16'b0000000000000000)
	);
endmodule
`default_nettype none
module controller (
	clk,
	reset,
	consumer_read_valid,
	consumer_read_address,
	consumer_read_ready,
	consumer_read_data,
	consumer_write_valid,
	consumer_write_address,
	consumer_write_data,
	consumer_write_ready,
	mem_read_valid,
	mem_read_address,
	mem_read_ready,
	mem_read_data,
	mem_write_valid,
	mem_write_address,
	mem_write_data,
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
	input wire [(NUM_CONSUMERS * ADDR_BITS) - 1:0] consumer_read_address;
	output reg [NUM_CONSUMERS - 1:0] consumer_read_ready;
	output reg [(NUM_CONSUMERS * DATA_BITS) - 1:0] consumer_read_data;
	input wire [NUM_CONSUMERS - 1:0] consumer_write_valid;
	input wire [(NUM_CONSUMERS * ADDR_BITS) - 1:0] consumer_write_address;
	input wire [(NUM_CONSUMERS * DATA_BITS) - 1:0] consumer_write_data;
	output reg [NUM_CONSUMERS - 1:0] consumer_write_ready;
	output reg [NUM_CHANNELS - 1:0] mem_read_valid;
	output reg [(NUM_CHANNELS * ADDR_BITS) - 1:0] mem_read_address;
	input wire [NUM_CHANNELS - 1:0] mem_read_ready;
	input wire [(NUM_CHANNELS * DATA_BITS) - 1:0] mem_read_data;
	output reg [NUM_CHANNELS - 1:0] mem_write_valid;
	output reg [(NUM_CHANNELS * ADDR_BITS) - 1:0] mem_write_address;
	output reg [(NUM_CHANNELS * DATA_BITS) - 1:0] mem_write_data;
	input wire [NUM_CHANNELS - 1:0] mem_write_ready;
	localparam IDLE = 3'b000;
	localparam READ_WAITING = 3'b010;
	localparam WRITE_WAITING = 3'b011;
	localparam READ_RELAYING = 3'b100;
	localparam WRITE_RELAYING = 3'b101;
	reg [2:0] controller_state [NUM_CHANNELS - 1:0];
	reg [$clog2(NUM_CONSUMERS) - 1:0] current_consumer [NUM_CHANNELS - 1:0];
	reg [NUM_CONSUMERS - 1:0] channel_serving_consumer;
	reg [NUM_CONSUMERS - 1:0] serving_next;
	integer sel;
	reg sel_is_write;
	integer i;
	integer j;
	integer k;
	always @(posedge clk)
		if (reset) begin
			mem_read_valid <= {NUM_CHANNELS {1'b0}};
			mem_write_valid <= {NUM_CHANNELS {1'b0}};
			consumer_read_ready <= {NUM_CONSUMERS {1'b0}};
			consumer_write_ready <= {NUM_CONSUMERS {1'b0}};
			channel_serving_consumer <= 0;
			serving_next <= {NUM_CONSUMERS {1'b0}};
			for (k = 0; k < NUM_CHANNELS; k = k + 1)
				begin
					mem_read_address[k * ADDR_BITS+:ADDR_BITS] <= {ADDR_BITS {1'b0}};
					mem_write_address[k * ADDR_BITS+:ADDR_BITS] <= {ADDR_BITS {1'b0}};
					mem_write_data[k * DATA_BITS+:DATA_BITS] <= {DATA_BITS {1'b0}};
				end
			for (k = 0; k < NUM_CONSUMERS; k = k + 1)
				consumer_read_data[k * DATA_BITS+:DATA_BITS] <= {DATA_BITS {1'b0}};
			for (k = 0; k < NUM_CHANNELS; k = k + 1)
				begin
					controller_state[k] <= IDLE;
					current_consumer[k] <= 0;
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
							current_consumer[i] <= sel[$clog2(NUM_CONSUMERS) - 1:0];
							if (!sel_is_write) begin
								mem_read_valid[i] <= 1'b1;
								mem_read_address[i * ADDR_BITS+:ADDR_BITS] <= consumer_read_address[sel * ADDR_BITS+:ADDR_BITS];
								controller_state[i] <= READ_WAITING;
							end
							else begin
								mem_write_valid[i] <= 1'b1;
								mem_write_address[i * ADDR_BITS+:ADDR_BITS] <= consumer_write_address[sel * ADDR_BITS+:ADDR_BITS];
								mem_write_data[i * DATA_BITS+:DATA_BITS] <= consumer_write_data[sel * DATA_BITS+:DATA_BITS];
								controller_state[i] <= WRITE_WAITING;
							end
						end
					end
					READ_WAITING:
						if (mem_read_ready[i]) begin
							mem_read_valid[i] <= 0;
							consumer_read_ready[current_consumer[i]] <= 1;
							consumer_read_data[current_consumer[i] * DATA_BITS+:DATA_BITS] <= mem_read_data[i * DATA_BITS+:DATA_BITS];
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
				endcase
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
	program_mem_read_valid,
	program_mem_read_address,
	program_mem_read_ready,
	program_mem_read_data,
	data_mem_read_valid,
	data_mem_read_address,
	data_mem_read_ready,
	data_mem_read_data,
	data_mem_write_valid,
	data_mem_write_address,
	data_mem_write_data,
	data_mem_write_ready
);
	parameter DATA_MEM_ADDR_BITS = 12;
	parameter DATA_MEM_DATA_BITS = 16;
	parameter PROGRAM_MEM_ADDR_BITS = 12;
	parameter PROGRAM_MEM_DATA_BITS = 16;
	parameter THREADS_PER_BLOCK = 4;
	parameter SYSTOLIC_SIZE = 8;
	parameter NUM_SYSTOLIC_ARRAYS = 8;
	parameter CACHE_SIZE = 64;
	input wire clk;
	input wire reset;
	input wire start;
	output wire done;
	input wire [7:0] block_id;
	input wire [$clog2(THREADS_PER_BLOCK):0] thread_count;
	output wire program_mem_read_valid;
	output wire [PROGRAM_MEM_ADDR_BITS - 1:0] program_mem_read_address;
	input wire program_mem_read_ready;
	input wire [PROGRAM_MEM_DATA_BITS - 1:0] program_mem_read_data;
	output wire [THREADS_PER_BLOCK - 1:0] data_mem_read_valid;
	output wire [(THREADS_PER_BLOCK * DATA_MEM_ADDR_BITS) - 1:0] data_mem_read_address;
	input wire [THREADS_PER_BLOCK - 1:0] data_mem_read_ready;
	input wire [(THREADS_PER_BLOCK * DATA_MEM_DATA_BITS) - 1:0] data_mem_read_data;
	output wire [THREADS_PER_BLOCK - 1:0] data_mem_write_valid;
	output wire [(THREADS_PER_BLOCK * DATA_MEM_ADDR_BITS) - 1:0] data_mem_write_address;
	output wire [(THREADS_PER_BLOCK * DATA_MEM_DATA_BITS) - 1:0] data_mem_write_data;
	input wire [THREADS_PER_BLOCK - 1:0] data_mem_write_ready;
	reg [2:0] core_state;
	reg [2:0] fetcher_state;
	reg [15:0] instruction;
	reg [PROGRAM_MEM_ADDR_BITS - 1:0] current_pc;
	wire [(THREADS_PER_BLOCK * PROGRAM_MEM_ADDR_BITS) - 1:0] next_pc;
	wire [DATA_MEM_DATA_BITS - 1:0] rs [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] rt [THREADS_PER_BLOCK - 1:0];
	wire [(THREADS_PER_BLOCK * 2) - 1:0] lsu_state;
	wire [DATA_MEM_DATA_BITS - 1:0] lsu_out [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] alu_out [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] fma_out [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] act_out [THREADS_PER_BLOCK - 1:0];
	reg [3:0] decoded_rd_address;
	reg [3:0] decoded_rs_address;
	reg [3:0] decoded_rt_address;
	reg [2:0] decoded_nzp;
	reg [7:0] decoded_immediate;
	reg decoded_reg_write_enable;
	reg decoded_mem_read_enable;
	reg decoded_mem_write_enable;
	reg decoded_nzp_write_enable;
	reg [2:0] decoded_reg_input_mux;
	reg [1:0] decoded_alu_arithmetic_mux;
	reg decoded_alu_output_mux;
	reg decoded_pc_mux;
	reg decoded_fma_enable;
	reg decoded_act_enable;
	reg [1:0] decoded_act_func;
	reg decoded_ret;
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
	wire [4:1] sv2v_tmp_decoder_instance_decoded_rd_address;
	always @(*) decoded_rd_address = sv2v_tmp_decoder_instance_decoded_rd_address;
	wire [4:1] sv2v_tmp_decoder_instance_decoded_rs_address;
	always @(*) decoded_rs_address = sv2v_tmp_decoder_instance_decoded_rs_address;
	wire [4:1] sv2v_tmp_decoder_instance_decoded_rt_address;
	always @(*) decoded_rt_address = sv2v_tmp_decoder_instance_decoded_rt_address;
	wire [3:1] sv2v_tmp_decoder_instance_decoded_nzp;
	always @(*) decoded_nzp = sv2v_tmp_decoder_instance_decoded_nzp;
	wire [8:1] sv2v_tmp_decoder_instance_decoded_immediate;
	always @(*) decoded_immediate = sv2v_tmp_decoder_instance_decoded_immediate;
	wire [1:1] sv2v_tmp_decoder_instance_decoded_reg_write_enable;
	always @(*) decoded_reg_write_enable = sv2v_tmp_decoder_instance_decoded_reg_write_enable;
	wire [1:1] sv2v_tmp_decoder_instance_decoded_mem_read_enable;
	always @(*) decoded_mem_read_enable = sv2v_tmp_decoder_instance_decoded_mem_read_enable;
	wire [1:1] sv2v_tmp_decoder_instance_decoded_mem_write_enable;
	always @(*) decoded_mem_write_enable = sv2v_tmp_decoder_instance_decoded_mem_write_enable;
	wire [1:1] sv2v_tmp_decoder_instance_decoded_nzp_write_enable;
	always @(*) decoded_nzp_write_enable = sv2v_tmp_decoder_instance_decoded_nzp_write_enable;
	wire [3:1] sv2v_tmp_decoder_instance_decoded_reg_input_mux;
	always @(*) decoded_reg_input_mux = sv2v_tmp_decoder_instance_decoded_reg_input_mux;
	wire [2:1] sv2v_tmp_decoder_instance_decoded_alu_arithmetic_mux;
	always @(*) decoded_alu_arithmetic_mux = sv2v_tmp_decoder_instance_decoded_alu_arithmetic_mux;
	wire [1:1] sv2v_tmp_decoder_instance_decoded_alu_output_mux;
	always @(*) decoded_alu_output_mux = sv2v_tmp_decoder_instance_decoded_alu_output_mux;
	wire [1:1] sv2v_tmp_decoder_instance_decoded_pc_mux;
	always @(*) decoded_pc_mux = sv2v_tmp_decoder_instance_decoded_pc_mux;
	wire [1:1] sv2v_tmp_decoder_instance_decoded_fma_enable;
	always @(*) decoded_fma_enable = sv2v_tmp_decoder_instance_decoded_fma_enable;
	wire [1:1] sv2v_tmp_decoder_instance_decoded_act_enable;
	always @(*) decoded_act_enable = sv2v_tmp_decoder_instance_decoded_act_enable;
	wire [2:1] sv2v_tmp_decoder_instance_decoded_act_func;
	always @(*) decoded_act_func = sv2v_tmp_decoder_instance_decoded_act_func;
	wire [1:1] sv2v_tmp_decoder_instance_decoded_ret;
	always @(*) decoded_ret = sv2v_tmp_decoder_instance_decoded_ret;
	decoder decoder_instance(
		.clk(clk),
		.reset(reset),
		.core_state(core_state),
		.instruction(instruction),
		.decoded_rd_address(sv2v_tmp_decoder_instance_decoded_rd_address),
		.decoded_rs_address(sv2v_tmp_decoder_instance_decoded_rs_address),
		.decoded_rt_address(sv2v_tmp_decoder_instance_decoded_rt_address),
		.decoded_nzp(sv2v_tmp_decoder_instance_decoded_nzp),
		.decoded_immediate(sv2v_tmp_decoder_instance_decoded_immediate),
		.decoded_reg_write_enable(sv2v_tmp_decoder_instance_decoded_reg_write_enable),
		.decoded_mem_read_enable(sv2v_tmp_decoder_instance_decoded_mem_read_enable),
		.decoded_mem_write_enable(sv2v_tmp_decoder_instance_decoded_mem_write_enable),
		.decoded_nzp_write_enable(sv2v_tmp_decoder_instance_decoded_nzp_write_enable),
		.decoded_reg_input_mux(sv2v_tmp_decoder_instance_decoded_reg_input_mux),
		.decoded_alu_arithmetic_mux(sv2v_tmp_decoder_instance_decoded_alu_arithmetic_mux),
		.decoded_alu_output_mux(sv2v_tmp_decoder_instance_decoded_alu_output_mux),
		.decoded_pc_mux(sv2v_tmp_decoder_instance_decoded_pc_mux),
		.decoded_fma_enable(sv2v_tmp_decoder_instance_decoded_fma_enable),
		.decoded_act_enable(sv2v_tmp_decoder_instance_decoded_act_enable),
		.decoded_act_func(sv2v_tmp_decoder_instance_decoded_act_func),
		.decoded_ret(sv2v_tmp_decoder_instance_decoded_ret)
	);
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
		.decoded_mem_read_enable(decoded_mem_read_enable),
		.decoded_mem_write_enable(decoded_mem_write_enable),
		.decoded_fma_enable(decoded_fma_enable),
		.decoded_ret(decoded_ret),
		.lsu_state(lsu_state),
		.current_pc(sv2v_tmp_scheduler_instance_current_pc),
		.next_pc(next_pc),
		.done(done)
	);
	genvar _gv_i_1;
	generate
		for (_gv_i_1 = 0; _gv_i_1 < THREADS_PER_BLOCK; _gv_i_1 = _gv_i_1 + 1) begin : threads
			localparam i = _gv_i_1;
			alu #(.DATA_BITS(DATA_MEM_DATA_BITS)) alu_instance(
				.clk(clk),
				.reset(reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.decoded_alu_arithmetic_mux(decoded_alu_arithmetic_mux),
				.decoded_alu_output_mux(decoded_alu_output_mux),
				.rs(rs[i]),
				.rt(rt[i]),
				.alu_out(alu_out[i])
			);
			fma #(.DATA_BITS(DATA_MEM_DATA_BITS)) fma_instance(
				.clk(clk),
				.reset(reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.decoded_fma_enable(decoded_fma_enable),
				.rs(rs[i]),
				.rt(rt[i]),
				.rq(rd_data[i]),
				.fma_out(fma_out[i])
			);
			activation #(.DATA_BITS(DATA_MEM_DATA_BITS)) activation_instance(
				.clk(clk),
				.reset(reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.activation_enable(decoded_act_enable),
				.activation_func(decoded_act_func),
				.unbiased_activation(rs[i]),
				.bias(rt[i]),
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
				.decoded_mem_read_enable(decoded_mem_read_enable),
				.decoded_mem_write_enable(decoded_mem_write_enable),
				.mem_read_valid(data_mem_read_valid[i]),
				.mem_read_address(data_mem_read_address[i * DATA_MEM_ADDR_BITS+:DATA_MEM_ADDR_BITS]),
				.mem_read_ready(data_mem_read_ready[i]),
				.mem_read_data(data_mem_read_data[i * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS]),
				.mem_write_valid(data_mem_write_valid[i]),
				.mem_write_address(data_mem_write_address[i * DATA_MEM_ADDR_BITS+:DATA_MEM_ADDR_BITS]),
				.mem_write_data(data_mem_write_data[i * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS]),
				.mem_write_ready(data_mem_write_ready[i]),
				.rs(rs[i]),
				.rt(rt[i]),
				.lsu_state(lsu_state[i * 2+:2]),
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
				.decoded_reg_write_enable(decoded_reg_write_enable),
				.decoded_reg_input_mux(decoded_reg_input_mux),
				.decoded_rd_address(decoded_rd_address),
				.decoded_rs_address(decoded_rs_address),
				.decoded_rt_address(decoded_rt_address),
				.decoded_immediate(decoded_immediate),
				.alu_out(alu_out[i]),
				.lsu_out(lsu_out[i]),
				.fma_out(fma_out[i]),
				.act_out(act_out[i]),
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
				.decoded_nzp(decoded_nzp),
				.decoded_immediate(decoded_immediate),
				.decoded_nzp_write_enable(decoded_nzp_write_enable),
				.decoded_pc_mux(decoded_pc_mux),
				.alu_out(alu_out[i]),
				.current_pc(current_pc),
				.next_pc(next_pc[i * PROGRAM_MEM_ADDR_BITS+:PROGRAM_MEM_ADDR_BITS]),
				.instruction(instruction)
			);
		end
	endgenerate
	wire [((SYSTOLIC_SIZE * SYSTOLIC_SIZE) * DATA_MEM_DATA_BITS) - 1:0] systolic_results;
	wire systolic_ready;
	wire [NUM_SYSTOLIC_ARRAYS - 1:0] all_systolic_ready;
	reg [$clog2(NUM_SYSTOLIC_ARRAYS) - 1:0] systolic_array_select;
	reg systolic_clear_acc;
	reg systolic_load_weights;
	reg systolic_compute_enable;
	reg systolic_broadcast_mode;
	wire signed [(SYSTOLIC_SIZE * DATA_MEM_DATA_BITS) - 1:0] systolic_a_inputs;
	wire signed [(SYSTOLIC_SIZE * DATA_MEM_DATA_BITS) - 1:0] systolic_b_inputs;
	genvar _gv_sa_idx_1;
	generate
		for (_gv_sa_idx_1 = 0; _gv_sa_idx_1 < SYSTOLIC_SIZE; _gv_sa_idx_1 = _gv_sa_idx_1 + 1) begin : systolic_input_init
			localparam sa_idx = _gv_sa_idx_1;
			assign systolic_a_inputs[sa_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = {DATA_MEM_DATA_BITS {1'b0}};
			assign systolic_b_inputs[sa_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = {DATA_MEM_DATA_BITS {1'b0}};
		end
	endgenerate
	always @(posedge clk)
		if (reset) begin
			systolic_array_select <= 0;
			systolic_clear_acc <= 1'b0;
			systolic_load_weights <= 1'b0;
			systolic_compute_enable <= 1'b0;
			systolic_broadcast_mode <= 1'b0;
		end
	systolic_array_cluster #(
		.DATA_BITS(DATA_MEM_DATA_BITS),
		.ARRAY_SIZE(SYSTOLIC_SIZE),
		.NUM_ARRAYS(NUM_SYSTOLIC_ARRAYS)
	) systolic_cluster_instance(
		.clk(clk),
		.reset(reset),
		.enable(1'b1),
		.array_select(systolic_array_select),
		.clear_acc(systolic_clear_acc),
		.load_weights(systolic_load_weights),
		.compute_enable(systolic_compute_enable),
		.broadcast_mode(systolic_broadcast_mode),
		.a_inputs(systolic_a_inputs),
		.b_inputs(systolic_b_inputs),
		.results(systolic_results),
		.ready(systolic_ready),
		.all_ready(all_systolic_ready)
	);
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
			decoded_act_enable = 0;
			decoded_act_func = 0;
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
			decoded_ret = 0;
			case (instruction[15:12])
				NOP:
					;
				BRnzp: decoded_pc_mux = 1;
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
	core_block_id,
	core_thread_count,
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
	output reg [(NUM_CORES * 8) - 1:0] core_block_id;
	output reg [($clog2(THREADS_PER_BLOCK) >= 0 ? (NUM_CORES * ($clog2(THREADS_PER_BLOCK) + 1)) - 1 : (NUM_CORES * (1 - $clog2(THREADS_PER_BLOCK))) + ($clog2(THREADS_PER_BLOCK) - 1)):($clog2(THREADS_PER_BLOCK) >= 0 ? 0 : $clog2(THREADS_PER_BLOCK) + 0)] core_thread_count;
	output reg done;
	wire [7:0] total_blocks;
	assign total_blocks = ((thread_count + THREADS_PER_BLOCK) - 1) / THREADS_PER_BLOCK;
	reg [7:0] blocks_dispatched;
	reg [7:0] blocks_done;
	reg start_execution;
	integer i;
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
					core_block_id[i * 8+:8] <= 0;
					core_thread_count[($clog2(THREADS_PER_BLOCK) >= 0 ? 0 : $clog2(THREADS_PER_BLOCK)) + (i * ($clog2(THREADS_PER_BLOCK) >= 0 ? $clog2(THREADS_PER_BLOCK) + 1 : 1 - $clog2(THREADS_PER_BLOCK)))+:($clog2(THREADS_PER_BLOCK) >= 0 ? $clog2(THREADS_PER_BLOCK) + 1 : 1 - $clog2(THREADS_PER_BLOCK))] <= THREADS_PER_BLOCK;
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
			for (i = 0; i < NUM_CORES; i = i + 1)
				if (core_reset[i]) begin
					core_reset[i] <= 0;
					if (blocks_dispatched < total_blocks) begin
						core_start[i] <= 1;
						core_block_id[i * 8+:8] <= blocks_dispatched;
						core_thread_count[($clog2(THREADS_PER_BLOCK) >= 0 ? 0 : $clog2(THREADS_PER_BLOCK)) + (i * ($clog2(THREADS_PER_BLOCK) >= 0 ? $clog2(THREADS_PER_BLOCK) + 1 : 1 - $clog2(THREADS_PER_BLOCK)))+:($clog2(THREADS_PER_BLOCK) >= 0 ? $clog2(THREADS_PER_BLOCK) + 1 : 1 - $clog2(THREADS_PER_BLOCK))] <= (blocks_dispatched == (total_blocks - 1) ? thread_count - (blocks_dispatched * THREADS_PER_BLOCK) : THREADS_PER_BLOCK);
						blocks_dispatched <= blocks_dispatched + 1;
					end
				end
			for (i = 0; i < NUM_CORES; i = i + 1)
				if (core_start[i] && core_done[i]) begin
					core_reset[i] <= 1;
					core_start[i] <= 0;
					blocks_done <= blocks_done + 1;
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
	localparam [DATA_BITS - 1:0] Q115_MIN = 16'h8000;
	localparam signed [31:0] Q115_MAX_S32 = 32'sd32767;
	localparam signed [31:0] Q115_MIN_S32 = -32'sd32768;
	reg [DATA_BITS - 1:0] r1_activation;
	reg [DATA_BITS - 1:0] r2_weight;
	reg [DATA_BITS - 1:0] r3_weighted;
	reg [DATA_BITS - 1:0] r4_accumulated;
	reg [DATA_BITS - 1:0] fma_out_reg;
	assign fma_out = fma_out_reg;
	wire signed [31:0] product_full_s32 = $signed(r1_activation) * $signed(r2_weight);
	wire signed [31:0] product_q115_s32 = product_full_s32 >>> 15;
	wire [DATA_BITS - 1:0] product_saturated = (product_q115_s32 > Q115_MAX_S32 ? Q115_MAX : (product_q115_s32 < Q115_MIN_S32 ? Q115_MIN : product_q115_s32[DATA_BITS - 1:0]));
	wire signed [31:0] acc_sum_s32 = $signed(r4_accumulated) + $signed(r3_weighted);
	wire [DATA_BITS - 1:0] accumulated_saturated = (acc_sum_s32 > Q115_MAX_S32 ? Q115_MAX : (acc_sum_s32 < Q115_MIN_S32 ? Q115_MIN : acc_sum_s32[DATA_BITS - 1:0]));
	reg exec_phase;
	always @(posedge clk)
		if (reset) begin
			r1_activation <= {DATA_BITS {1'b0}};
			r2_weight <= {DATA_BITS {1'b0}};
			r3_weighted <= {DATA_BITS {1'b0}};
			r4_accumulated <= {DATA_BITS {1'b0}};
			fma_out_reg <= {DATA_BITS {1'b0}};
			exec_phase <= 1'b0;
		end
		else if (enable) begin
			if ((core_state != 3'b101) || !decoded_fma_enable)
				exec_phase <= 1'b0;
			if (core_state == 3'b011) begin
				r1_activation <= rs;
				r2_weight <= rt;
				r4_accumulated <= rq;
			end
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
	program_mem_read_address,
	program_mem_read_ready,
	program_mem_read_data,
	data_mem_read_valid,
	data_mem_read_address,
	data_mem_read_ready,
	data_mem_read_data,
	data_mem_write_valid,
	data_mem_write_address,
	data_mem_write_data,
	data_mem_write_ready
);
	parameter DATA_MEM_ADDR_BITS = 12;
	parameter DATA_MEM_DATA_BITS = 16;
	parameter DATA_MEM_NUM_CHANNELS = 16;
	parameter PROGRAM_MEM_ADDR_BITS = 12;
	parameter PROGRAM_MEM_DATA_BITS = 16;
	parameter PROGRAM_MEM_NUM_CHANNELS = 4;
	parameter NUM_CORES = 4;
	parameter THREADS_PER_BLOCK = 4;
	parameter SYSTOLIC_SIZE = 8;
	parameter NUM_SYSTOLIC_ARRAYS = 8;
	input wire clk;
	input wire reset;
	input wire start;
	output wire done;
	input wire device_control_write_enable;
	input wire [7:0] device_control_data;
	output wire [PROGRAM_MEM_NUM_CHANNELS - 1:0] program_mem_read_valid;
	output wire [(PROGRAM_MEM_NUM_CHANNELS * PROGRAM_MEM_ADDR_BITS) - 1:0] program_mem_read_address;
	input wire [PROGRAM_MEM_NUM_CHANNELS - 1:0] program_mem_read_ready;
	input wire [(PROGRAM_MEM_NUM_CHANNELS * PROGRAM_MEM_DATA_BITS) - 1:0] program_mem_read_data;
	output wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_read_valid;
	output wire [(DATA_MEM_NUM_CHANNELS * DATA_MEM_ADDR_BITS) - 1:0] data_mem_read_address;
	input wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_read_ready;
	input wire [(DATA_MEM_NUM_CHANNELS * DATA_MEM_DATA_BITS) - 1:0] data_mem_read_data;
	output wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_write_valid;
	output wire [(DATA_MEM_NUM_CHANNELS * DATA_MEM_ADDR_BITS) - 1:0] data_mem_write_address;
	output wire [(DATA_MEM_NUM_CHANNELS * DATA_MEM_DATA_BITS) - 1:0] data_mem_write_data;
	input wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_write_ready;
	wire [7:0] thread_count;
	reg [NUM_CORES - 1:0] core_start;
	reg [NUM_CORES - 1:0] core_reset;
	wire [NUM_CORES - 1:0] core_done;
	reg [(NUM_CORES * 8) - 1:0] core_block_id;
	reg [($clog2(THREADS_PER_BLOCK) >= 0 ? (NUM_CORES * ($clog2(THREADS_PER_BLOCK) + 1)) - 1 : (NUM_CORES * (1 - $clog2(THREADS_PER_BLOCK))) + ($clog2(THREADS_PER_BLOCK) - 1)):($clog2(THREADS_PER_BLOCK) >= 0 ? 0 : $clog2(THREADS_PER_BLOCK) + 0)] core_thread_count;
	localparam NUM_LSUS = NUM_CORES * THREADS_PER_BLOCK;
	reg [NUM_LSUS - 1:0] lsu_read_valid;
	reg [(NUM_LSUS * DATA_MEM_ADDR_BITS) - 1:0] lsu_read_address;
	wire [NUM_LSUS - 1:0] lsu_read_ready;
	wire [(NUM_LSUS * DATA_MEM_DATA_BITS) - 1:0] lsu_read_data;
	reg [NUM_LSUS - 1:0] lsu_write_valid;
	reg [(NUM_LSUS * DATA_MEM_ADDR_BITS) - 1:0] lsu_write_address;
	reg [(NUM_LSUS * DATA_MEM_DATA_BITS) - 1:0] lsu_write_data;
	wire [NUM_LSUS - 1:0] lsu_write_ready;
	localparam NUM_FETCHERS = NUM_CORES;
	wire [NUM_FETCHERS - 1:0] fetcher_read_valid;
	wire [(NUM_FETCHERS * PROGRAM_MEM_ADDR_BITS) - 1:0] fetcher_read_address;
	wire [NUM_FETCHERS - 1:0] fetcher_read_ready;
	wire [(NUM_FETCHERS * PROGRAM_MEM_DATA_BITS) - 1:0] fetcher_read_data;
	wire [NUM_FETCHERS - 1:0] prog_mem_write_ready_unused;
	wire [PROGRAM_MEM_NUM_CHANNELS - 1:0] prog_ext_write_valid_unused;
	wire [(PROGRAM_MEM_NUM_CHANNELS * PROGRAM_MEM_ADDR_BITS) - 1:0] prog_ext_write_address_unused;
	wire [(PROGRAM_MEM_NUM_CHANNELS * PROGRAM_MEM_DATA_BITS) - 1:0] prog_ext_write_data_unused;
	wire [(NUM_FETCHERS * PROGRAM_MEM_ADDR_BITS) - 1:0] fetcher_write_address_unused;
	wire [(NUM_FETCHERS * PROGRAM_MEM_DATA_BITS) - 1:0] fetcher_write_data_unused;
	genvar _gv_fw_1;
	generate
		for (_gv_fw_1 = 0; _gv_fw_1 < NUM_FETCHERS; _gv_fw_1 = _gv_fw_1 + 1) begin : prog_write_tieoff
			localparam fw = _gv_fw_1;
			assign fetcher_write_address_unused[fw * PROGRAM_MEM_ADDR_BITS+:PROGRAM_MEM_ADDR_BITS] = {PROGRAM_MEM_ADDR_BITS {1'b0}};
			assign fetcher_write_data_unused[fw * PROGRAM_MEM_DATA_BITS+:PROGRAM_MEM_DATA_BITS] = {PROGRAM_MEM_DATA_BITS {1'b0}};
		end
	endgenerate
	dcr dcr_instance(
		.clk(clk),
		.reset(reset),
		.device_control_write_enable(device_control_write_enable),
		.device_control_data(device_control_data),
		.thread_count(thread_count)
	);
	controller #(
		.ADDR_BITS(DATA_MEM_ADDR_BITS),
		.DATA_BITS(DATA_MEM_DATA_BITS),
		.NUM_CONSUMERS(NUM_LSUS),
		.NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
	) data_memory_controller(
		.clk(clk),
		.reset(reset),
		.consumer_read_valid(lsu_read_valid),
		.consumer_read_address(lsu_read_address),
		.consumer_read_ready(lsu_read_ready),
		.consumer_read_data(lsu_read_data),
		.consumer_write_valid(lsu_write_valid),
		.consumer_write_address(lsu_write_address),
		.consumer_write_data(lsu_write_data),
		.consumer_write_ready(lsu_write_ready),
		.mem_read_valid(data_mem_read_valid),
		.mem_read_address(data_mem_read_address),
		.mem_read_ready(data_mem_read_ready),
		.mem_read_data(data_mem_read_data),
		.mem_write_valid(data_mem_write_valid),
		.mem_write_address(data_mem_write_address),
		.mem_write_data(data_mem_write_data),
		.mem_write_ready(data_mem_write_ready)
	);
	controller #(
		.ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
		.DATA_BITS(PROGRAM_MEM_DATA_BITS),
		.NUM_CONSUMERS(NUM_FETCHERS),
		.NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
		.WRITE_ENABLE(0)
	) program_memory_controller(
		.clk(clk),
		.reset(reset),
		.consumer_read_valid(fetcher_read_valid),
		.consumer_read_address(fetcher_read_address),
		.consumer_read_ready(fetcher_read_ready),
		.consumer_read_data(fetcher_read_data),
		.consumer_write_valid({NUM_FETCHERS {1'b0}}),
		.consumer_write_address(fetcher_write_address_unused),
		.consumer_write_data(fetcher_write_data_unused),
		.consumer_write_ready(prog_mem_write_ready_unused),
		.mem_read_valid(program_mem_read_valid),
		.mem_read_address(program_mem_read_address),
		.mem_read_ready(program_mem_read_ready),
		.mem_read_data(program_mem_read_data),
		.mem_write_valid(prog_ext_write_valid_unused),
		.mem_write_address(prog_ext_write_address_unused),
		.mem_write_data(prog_ext_write_data_unused),
		.mem_write_ready({PROGRAM_MEM_NUM_CHANNELS {1'b0}})
	);
	wire [NUM_CORES:1] sv2v_tmp_dispatch_instance_core_start;
	always @(*) core_start = sv2v_tmp_dispatch_instance_core_start;
	wire [NUM_CORES:1] sv2v_tmp_dispatch_instance_core_reset;
	always @(*) core_reset = sv2v_tmp_dispatch_instance_core_reset;
	wire [NUM_CORES * 8:1] sv2v_tmp_dispatch_instance_core_block_id;
	always @(*) core_block_id = sv2v_tmp_dispatch_instance_core_block_id;
	wire [(($clog2(THREADS_PER_BLOCK) >= 0 ? (NUM_CORES * ($clog2(THREADS_PER_BLOCK) + 1)) - 1 : (NUM_CORES * (1 - $clog2(THREADS_PER_BLOCK))) + ($clog2(THREADS_PER_BLOCK) - 1)) >= ($clog2(THREADS_PER_BLOCK) >= 0 ? 0 : $clog2(THREADS_PER_BLOCK) + 0) ? (($clog2(THREADS_PER_BLOCK) >= 0 ? (NUM_CORES * ($clog2(THREADS_PER_BLOCK) + 1)) - 1 : (NUM_CORES * (1 - $clog2(THREADS_PER_BLOCK))) + ($clog2(THREADS_PER_BLOCK) - 1)) - ($clog2(THREADS_PER_BLOCK) >= 0 ? 0 : $clog2(THREADS_PER_BLOCK) + 0)) + 1 : (($clog2(THREADS_PER_BLOCK) >= 0 ? 0 : $clog2(THREADS_PER_BLOCK) + 0) - ($clog2(THREADS_PER_BLOCK) >= 0 ? (NUM_CORES * ($clog2(THREADS_PER_BLOCK) + 1)) - 1 : (NUM_CORES * (1 - $clog2(THREADS_PER_BLOCK))) + ($clog2(THREADS_PER_BLOCK) - 1))) + 1):1] sv2v_tmp_dispatch_instance_core_thread_count;
	always @(*) core_thread_count = sv2v_tmp_dispatch_instance_core_thread_count;
	dispatch #(
		.NUM_CORES(NUM_CORES),
		.THREADS_PER_BLOCK(THREADS_PER_BLOCK)
	) dispatch_instance(
		.clk(clk),
		.reset(reset),
		.start(start),
		.thread_count(thread_count),
		.core_done(core_done),
		.core_start(sv2v_tmp_dispatch_instance_core_start),
		.core_reset(sv2v_tmp_dispatch_instance_core_reset),
		.core_block_id(sv2v_tmp_dispatch_instance_core_block_id),
		.core_thread_count(sv2v_tmp_dispatch_instance_core_thread_count),
		.done(done)
	);
	genvar _gv_i_2;
	generate
		for (_gv_i_2 = 0; _gv_i_2 < NUM_CORES; _gv_i_2 = _gv_i_2 + 1) begin : cores
			localparam i = _gv_i_2;
			wire [THREADS_PER_BLOCK - 1:0] core_lsu_read_valid;
			wire [(THREADS_PER_BLOCK * DATA_MEM_ADDR_BITS) - 1:0] core_lsu_read_address;
			reg [THREADS_PER_BLOCK - 1:0] core_lsu_read_ready;
			reg [(THREADS_PER_BLOCK * DATA_MEM_DATA_BITS) - 1:0] core_lsu_read_data;
			wire [THREADS_PER_BLOCK - 1:0] core_lsu_write_valid;
			wire [(THREADS_PER_BLOCK * DATA_MEM_ADDR_BITS) - 1:0] core_lsu_write_address;
			wire [(THREADS_PER_BLOCK * DATA_MEM_DATA_BITS) - 1:0] core_lsu_write_data;
			reg [THREADS_PER_BLOCK - 1:0] core_lsu_write_ready;
			genvar _gv_j_1;
			for (_gv_j_1 = 0; _gv_j_1 < THREADS_PER_BLOCK; _gv_j_1 = _gv_j_1 + 1) begin : lsu_passthrough
				localparam j = _gv_j_1;
				localparam lsu_index = (i * THREADS_PER_BLOCK) + j;
				always @(posedge clk) begin
					lsu_read_valid[lsu_index] <= core_lsu_read_valid[j];
					lsu_read_address[lsu_index * DATA_MEM_ADDR_BITS+:DATA_MEM_ADDR_BITS] <= core_lsu_read_address[j * DATA_MEM_ADDR_BITS+:DATA_MEM_ADDR_BITS];
					lsu_write_valid[lsu_index] <= core_lsu_write_valid[j];
					lsu_write_address[lsu_index * DATA_MEM_ADDR_BITS+:DATA_MEM_ADDR_BITS] <= core_lsu_write_address[j * DATA_MEM_ADDR_BITS+:DATA_MEM_ADDR_BITS];
					lsu_write_data[lsu_index * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] <= core_lsu_write_data[j * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS];
					core_lsu_read_ready[j] <= lsu_read_ready[lsu_index];
					core_lsu_read_data[j * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] <= lsu_read_data[lsu_index * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS];
					core_lsu_write_ready[j] <= lsu_write_ready[lsu_index];
				end
			end
			core #(
				.DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
				.DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
				.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
				.PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
				.THREADS_PER_BLOCK(THREADS_PER_BLOCK),
				.SYSTOLIC_SIZE(SYSTOLIC_SIZE),
				.NUM_SYSTOLIC_ARRAYS(NUM_SYSTOLIC_ARRAYS),
				.CACHE_SIZE(64)
			) core_instance(
				.clk(clk),
				.reset(core_reset[i]),
				.start(core_start[i]),
				.done(core_done[i]),
				.block_id(core_block_id[i * 8+:8]),
				.thread_count(core_thread_count[($clog2(THREADS_PER_BLOCK) >= 0 ? 0 : $clog2(THREADS_PER_BLOCK)) + (i * ($clog2(THREADS_PER_BLOCK) >= 0 ? $clog2(THREADS_PER_BLOCK) + 1 : 1 - $clog2(THREADS_PER_BLOCK)))+:($clog2(THREADS_PER_BLOCK) >= 0 ? $clog2(THREADS_PER_BLOCK) + 1 : 1 - $clog2(THREADS_PER_BLOCK))]),
				.program_mem_read_valid(fetcher_read_valid[i]),
				.program_mem_read_address(fetcher_read_address[i * PROGRAM_MEM_ADDR_BITS+:PROGRAM_MEM_ADDR_BITS]),
				.program_mem_read_ready(fetcher_read_ready[i]),
				.program_mem_read_data(fetcher_read_data[i * PROGRAM_MEM_DATA_BITS+:PROGRAM_MEM_DATA_BITS]),
				.data_mem_read_valid(core_lsu_read_valid),
				.data_mem_read_address(core_lsu_read_address),
				.data_mem_read_ready(core_lsu_read_ready),
				.data_mem_read_data(core_lsu_read_data),
				.data_mem_write_valid(core_lsu_write_valid),
				.data_mem_write_address(core_lsu_write_address),
				.data_mem_write_data(core_lsu_write_data),
				.data_mem_write_ready(core_lsu_write_ready)
			);
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
	parameter ADDR_BITS = 8;
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
	reg [$clog2(MAX_SEQ_LEN) - 1:0] write_ptr;
	reg [$clog2(MAX_SEQ_LEN) - 1:0] read_ptr;
	reg [$clog2(MAX_SEQ_LEN) - 1:0] window_start;
	wire [$clog2(MAX_SEQ_LEN * HEAD_DIM) - 1:0] key_write_addr = (seq_position * HEAD_DIM) + key_dim_sel;
	wire [$clog2(MAX_SEQ_LEN * HEAD_DIM) - 1:0] value_write_addr = (seq_position * HEAD_DIM) + value_dim_sel;
	wire [$clog2(MAX_SEQ_LEN * HEAD_DIM) - 1:0] key_read_addr = (key_read_pos * HEAD_DIM) + key_read_dim;
	wire [$clog2(MAX_SEQ_LEN * HEAD_DIM) - 1:0] value_read_addr = (value_read_pos * HEAD_DIM) + value_read_dim;
	wire [$clog2(MAX_SEQ_LEN) - 1:0] effective_key_pos = (sliding_window_en ? (key_read_pos - window_start) % MAX_SEQ_LEN : key_read_pos);
	wire [$clog2(MAX_SEQ_LEN) - 1:0] effective_value_pos = (sliding_window_en ? (value_read_pos - window_start) % MAX_SEQ_LEN : value_read_pos);
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
	always @(posedge clk)
		if (reset || clear_cache) begin
			cache_length <= 0;
			write_ptr <= 0;
			read_ptr <= 0;
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
				if (append_mode && (value_dim_sel == (HEAD_DIM - 1))) begin
					if (cache_length < MAX_SEQ_LEN)
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
	wire position_valid = (key_read_pos < cache_length) || (sliding_window_en && (key_read_pos >= window_start));
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
	output reg [ADDR_BITS - 1:0] mem_read_address;
	input wire mem_read_ready;
	input wire [DATA_BITS - 1:0] mem_read_data;
	output reg mem_write_valid;
	output reg [ADDR_BITS - 1:0] mem_write_address;
	output reg [DATA_BITS - 1:0] mem_write_data;
	input wire mem_write_ready;
	output reg [1:0] lsu_state;
	output reg [DATA_BITS - 1:0] lsu_out;
	localparam IDLE = 2'b00;
	localparam REQUESTING = 2'b01;
	localparam WAITING = 2'b10;
	localparam DONE = 2'b11;
	always @(posedge clk)
		if (reset) begin
			lsu_state <= IDLE;
			lsu_out <= {DATA_BITS {1'b0}};
			mem_read_valid <= 0;
			mem_read_address <= {ADDR_BITS {1'b0}};
			mem_write_valid <= 0;
			mem_write_address <= {ADDR_BITS {1'b0}};
			mem_write_data <= {DATA_BITS {1'b0}};
		end
		else if (enable) begin
			if (decoded_mem_read_enable)
				case (lsu_state)
					IDLE:
						if (core_state == 3'b011)
							lsu_state <= REQUESTING;
					REQUESTING: begin
						mem_read_valid <= 1;
						mem_read_address <= rs[ADDR_BITS - 1:0];
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
						mem_write_address <= rs[ADDR_BITS - 1:0];
						mem_write_data <= rt;
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
	req_address,
	req_is_write,
	req_write_data,
	req_ready,
	req_read_data,
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
	input wire [(NUM_REQUESTS * ADDR_BITS) - 1:0] req_address;
	input wire [NUM_REQUESTS - 1:0] req_is_write;
	input wire [(NUM_REQUESTS * DATA_BITS) - 1:0] req_write_data;
	output reg [NUM_REQUESTS - 1:0] req_ready;
	output reg [(NUM_REQUESTS * DATA_BITS) - 1:0] req_read_data;
	output reg coalesced_valid;
	output reg [ADDR_BITS - 1:0] coalesced_base_addr;
	output reg coalesced_is_write;
	output reg [$clog2(COALESCE_WIDTH):0] coalesced_count;
	output reg [(DATA_BITS * COALESCE_WIDTH) - 1:0] coalesced_write_data;
	input wire coalesced_ready;
	input wire [(DATA_BITS * COALESCE_WIDTH) - 1:0] coalesced_read_data;
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
	genvar _gv_g_1;
	generate
		for (_gv_g_1 = 0; _gv_g_1 < NUM_REQUESTS; _gv_g_1 = _gv_g_1 + 1) begin : seq_check
			localparam g = _gv_g_1;
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
					req_read_data[m * DATA_BITS+:DATA_BITS] <= {DATA_BITS {1'b0}};
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
								pending_addr[m] <= req_address[m * ADDR_BITS+:ADDR_BITS];
								pending_is_write[m] <= req_is_write[m];
								pending_data[m] <= req_write_data[m * DATA_BITS+:DATA_BITS];
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
								req_read_data[m * DATA_BITS+:DATA_BITS] <= coalesced_read_data[(pending_addr[m] - base_address) * DATA_BITS+:DATA_BITS];
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
	decoded_immediate,
	decoded_nzp_write_enable,
	decoded_pc_mux,
	alu_out,
	current_pc,
	next_pc,
	instruction
);
	parameter DATA_MEM_DATA_BITS = 16;
	parameter PROGRAM_MEM_ADDR_BITS = 8;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire [2:0] core_state;
	input wire [2:0] decoded_nzp;
	input wire [7:0] decoded_immediate;
	input wire decoded_nzp_write_enable;
	input wire decoded_pc_mux;
	input wire [DATA_MEM_DATA_BITS - 1:0] alu_out;
	input wire [PROGRAM_MEM_ADDR_BITS - 1:0] current_pc;
	output reg [PROGRAM_MEM_ADDR_BITS - 1:0] next_pc;
	input wire [15:0] instruction;
	reg [2:0] nzp;
	wire signed [PROGRAM_MEM_ADDR_BITS:0] pc_plus_one_s = $signed({1'b0, current_pc}) + $signed({{PROGRAM_MEM_ADDR_BITS {1'b0}}, 1'b1});
	localparam integer BR_OFF_W = PROGRAM_MEM_ADDR_BITS + 1;
	wire signed [BR_OFF_W - 1:0] br_off9_s = $signed({{BR_OFF_W - 9 {instruction[8]}}, instruction[8:0]});
	wire signed [PROGRAM_MEM_ADDR_BITS:0] br_target_s = pc_plus_one_s + br_off9_s;
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] br_target = br_target_s[PROGRAM_MEM_ADDR_BITS - 1:0];
	always @(posedge clk)
		if (reset) begin
			nzp <= 3'b000;
			next_pc <= 0;
		end
		else if (enable) begin
			if (core_state == 3'b101) begin
				if (decoded_pc_mux == 1) begin
					if ((nzp & decoded_nzp) != 3'b000)
						next_pc <= br_target;
					else
						next_pc <= current_pc + 1;
				end
				else
					next_pc <= current_pc + 1;
			end
			if (core_state == 3'b110) begin
				if (decoded_nzp_write_enable) begin
					nzp[2] <= alu_out[2];
					nzp[1] <= alu_out[1];
					nzp[0] <= alu_out[0];
				end
			end
		end
endmodule
`default_nettype none
module pipeline (
	clk,
	reset,
	enable,
	flush,
	fetched_instruction,
	fetch_valid,
	decode_instruction,
	decode_valid,
	execute_result,
	execute_ready,
	execute_rd,
	memory_data,
	memory_ready,
	memory_is_load,
	writeback_data,
	writeback_rd,
	writeback_enable,
	pipeline_stall,
	forward_data,
	forward_rd,
	forward_valid
);
	parameter DATA_BITS = 16;
	parameter ADDR_BITS = 8;
	parameter INSTR_BITS = 16;
	parameter REG_BITS = 4;
	input wire clk;
	input wire reset;
	input wire enable;
	input wire flush;
	input wire [INSTR_BITS - 1:0] fetched_instruction;
	input wire fetch_valid;
	output reg [INSTR_BITS - 1:0] decode_instruction;
	output reg decode_valid;
	input wire [DATA_BITS - 1:0] execute_result;
	input wire execute_ready;
	input wire [REG_BITS - 1:0] execute_rd;
	input wire [DATA_BITS - 1:0] memory_data;
	input wire memory_ready;
	input wire memory_is_load;
	output reg [DATA_BITS - 1:0] writeback_data;
	output reg [REG_BITS - 1:0] writeback_rd;
	output reg writeback_enable;
	output reg pipeline_stall;
	output reg [DATA_BITS - 1:0] forward_data;
	output reg [REG_BITS - 1:0] forward_rd;
	output reg forward_valid;
	localparam FETCH = 3'd0;
	localparam DECODE = 3'd1;
	localparam EXECUTE = 3'd2;
	localparam MEMORY = 3'd3;
	localparam WRITEBACK = 3'd4;
	reg [INSTR_BITS - 1:0] if_id_instruction;
	reg if_id_valid;
	reg [INSTR_BITS - 1:0] id_ex_instruction;
	reg [REG_BITS - 1:0] id_ex_rd;
	reg [REG_BITS - 1:0] id_ex_rs;
	reg [REG_BITS - 1:0] id_ex_rt;
	reg id_ex_valid;
	reg id_ex_is_load;
	reg id_ex_is_store;
	reg id_ex_is_alu;
	reg id_ex_is_fma;
	reg [DATA_BITS - 1:0] ex_mem_result;
	reg [REG_BITS - 1:0] ex_mem_rd;
	reg ex_mem_valid;
	reg ex_mem_is_load;
	reg ex_mem_writes_reg;
	reg [DATA_BITS - 1:0] mem_wb_data;
	reg [REG_BITS - 1:0] mem_wb_rd;
	reg mem_wb_valid;
	reg mem_wb_writes_reg;
	wire [3:0] decode_opcode = if_id_instruction[15:12];
	wire [REG_BITS - 1:0] decode_rd_field = if_id_instruction[11:8];
	wire [REG_BITS - 1:0] decode_rs_field = if_id_instruction[7:4];
	wire [REG_BITS - 1:0] decode_rt_field = if_id_instruction[3:0];
	localparam OP_NOP = 4'b0000;
	localparam OP_BRnzp = 4'b0001;
	localparam OP_CMP = 4'b0010;
	localparam OP_ADD = 4'b0011;
	localparam OP_SUB = 4'b0100;
	localparam OP_MUL = 4'b0101;
	localparam OP_DIV = 4'b0110;
	localparam OP_LDR = 4'b0111;
	localparam OP_STR = 4'b1000;
	localparam OP_CONST = 4'b1001;
	localparam OP_FMA = 4'b1010;
	localparam OP_RET = 4'b1111;
	wire decode_is_load = decode_opcode == OP_LDR;
	wire decode_is_store = decode_opcode == OP_STR;
	wire decode_is_alu = ((((decode_opcode == OP_ADD) || (decode_opcode == OP_SUB)) || (decode_opcode == OP_MUL)) || (decode_opcode == OP_DIV)) || (decode_opcode == OP_CMP);
	wire decode_is_fma = decode_opcode == OP_FMA;
	wire decode_writes_reg = ((decode_is_load || decode_is_alu) || decode_is_fma) || (decode_opcode == OP_CONST);
	reg id_ex_writes_reg;
	wire raw_hazard_ex = (id_ex_valid && id_ex_writes_reg) && ((id_ex_rd == decode_rs_field) || (id_ex_rd == decode_rt_field));
	wire raw_hazard_mem = (ex_mem_valid && ex_mem_writes_reg) && ((ex_mem_rd == decode_rs_field) || (ex_mem_rd == decode_rt_field));
	wire load_use_hazard = (id_ex_valid && id_ex_is_load) && ((id_ex_rd == decode_rs_field) || (id_ex_rd == decode_rt_field));
	always @(*) begin
		forward_valid = 1'b0;
		forward_data = {DATA_BITS {1'b0}};
		forward_rd = {REG_BITS {1'b0}};
		if (ex_mem_valid && ex_mem_writes_reg) begin
			forward_valid = 1'b1;
			forward_data = ex_mem_result;
			forward_rd = ex_mem_rd;
		end
		else if (mem_wb_valid && mem_wb_writes_reg) begin
			forward_valid = 1'b1;
			forward_data = mem_wb_data;
			forward_rd = mem_wb_rd;
		end
	end
	always @(*) begin
		pipeline_stall = 1'b0;
		if (load_use_hazard && if_id_valid)
			pipeline_stall = 1'b1;
		if ((ex_mem_valid && ex_mem_is_load) && !memory_ready)
			pipeline_stall = 1'b1;
		if ((id_ex_valid && (id_ex_is_alu || id_ex_is_fma)) && !execute_ready)
			pipeline_stall = 1'b1;
	end
	always @(posedge clk)
		if (reset) begin
			if_id_instruction <= {INSTR_BITS {1'b0}};
			if_id_valid <= 1'b0;
			id_ex_instruction <= {INSTR_BITS {1'b0}};
			id_ex_rd <= {REG_BITS {1'b0}};
			id_ex_rs <= {REG_BITS {1'b0}};
			id_ex_rt <= {REG_BITS {1'b0}};
			id_ex_valid <= 1'b0;
			id_ex_is_load <= 1'b0;
			id_ex_is_store <= 1'b0;
			id_ex_is_alu <= 1'b0;
			id_ex_is_fma <= 1'b0;
			id_ex_writes_reg <= 1'b0;
			ex_mem_result <= {DATA_BITS {1'b0}};
			ex_mem_rd <= {REG_BITS {1'b0}};
			ex_mem_valid <= 1'b0;
			ex_mem_is_load <= 1'b0;
			ex_mem_writes_reg <= 1'b0;
			mem_wb_data <= {DATA_BITS {1'b0}};
			mem_wb_rd <= {REG_BITS {1'b0}};
			mem_wb_valid <= 1'b0;
			mem_wb_writes_reg <= 1'b0;
			decode_instruction <= {INSTR_BITS {1'b0}};
			decode_valid <= 1'b0;
			writeback_data <= {DATA_BITS {1'b0}};
			writeback_rd <= {REG_BITS {1'b0}};
			writeback_enable <= 1'b0;
		end
		else if (flush) begin
			if_id_valid <= 1'b0;
			id_ex_valid <= 1'b0;
			ex_mem_valid <= 1'b0;
			decode_valid <= 1'b0;
		end
		else if (enable && !pipeline_stall) begin
			if_id_instruction <= fetched_instruction;
			if_id_valid <= fetch_valid;
			decode_instruction <= if_id_instruction;
			decode_valid <= if_id_valid;
			id_ex_instruction <= if_id_instruction;
			id_ex_rd <= decode_rd_field;
			id_ex_rs <= decode_rs_field;
			id_ex_rt <= decode_rt_field;
			id_ex_valid <= if_id_valid;
			id_ex_is_load <= decode_is_load;
			id_ex_is_store <= decode_is_store;
			id_ex_is_alu <= decode_is_alu;
			id_ex_is_fma <= decode_is_fma;
			id_ex_writes_reg <= decode_writes_reg;
			ex_mem_result <= execute_result;
			ex_mem_rd <= id_ex_rd;
			ex_mem_valid <= id_ex_valid && execute_ready;
			ex_mem_is_load <= id_ex_is_load;
			ex_mem_writes_reg <= id_ex_writes_reg;
			if (ex_mem_is_load && memory_ready)
				mem_wb_data <= memory_data;
			else
				mem_wb_data <= ex_mem_result;
			mem_wb_rd <= ex_mem_rd;
			mem_wb_valid <= ex_mem_valid;
			mem_wb_writes_reg <= ex_mem_writes_reg;
			writeback_data <= mem_wb_data;
			writeback_rd <= mem_wb_rd;
			writeback_enable <= mem_wb_valid && mem_wb_writes_reg;
		end
		else if (enable && pipeline_stall) begin
			if (load_use_hazard)
				id_ex_valid <= 1'b0;
		end
	wire [4:0] stage_valid = {if_id_valid, id_ex_valid, ex_mem_valid, mem_wb_valid, writeback_enable};
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
	decoded_reg_write_enable,
	decoded_reg_input_mux,
	decoded_immediate,
	alu_out,
	lsu_out,
	fma_out,
	act_out,
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
	input wire decoded_reg_write_enable;
	input wire [2:0] decoded_reg_input_mux;
	input wire [7:0] decoded_immediate;
	input wire [DATA_BITS - 1:0] alu_out;
	input wire [DATA_BITS - 1:0] lsu_out;
	input wire [DATA_BITS - 1:0] fma_out;
	input wire [DATA_BITS - 1:0] act_out;
	output wire [DATA_BITS - 1:0] rs;
	output wire [DATA_BITS - 1:0] rt;
	output wire [DATA_BITS - 1:0] rd_data;
	localparam [2:0] MUX_ALU = 3'b000;
	localparam [2:0] MUX_MEMORY = 3'b001;
	localparam [2:0] MUX_CONSTANT = 3'b010;
	localparam [2:0] MUX_FMA = 3'b011;
	localparam [2:0] MUX_ACT = 3'b100;
	reg [DATA_BITS - 1:0] registers [15:0];
	assign rs = (enable ? registers[decoded_rs_address] : {DATA_BITS {1'b0}});
	assign rt = (enable ? registers[decoded_rt_address] : {DATA_BITS {1'b0}});
	assign rd_data = (enable ? registers[decoded_rd_address] : {DATA_BITS {1'b0}});
	wire [DATA_BITS - 1:0] immediate_extended;
	assign immediate_extended = {{8 {decoded_immediate[7]}}, decoded_immediate};
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
			registers[13] <= {DATA_BITS {1'b0}};
			registers[14] <= {{DATA_BITS - 8 {1'b0}}, THREADS_PER_BLOCK[7:0]};
			registers[15] <= {{DATA_BITS - 8 {1'b0}}, THREAD_ID[7:0]};
		end
		else if (enable) begin
			registers[13] <= {{DATA_BITS - 8 {1'b0}}, block_id};
			if (core_state == 3'b110) begin
				if (decoded_reg_write_enable && (decoded_rd_address < 13))
					case (decoded_reg_input_mux)
						MUX_ALU: registers[decoded_rd_address] <= alu_out;
						MUX_MEMORY: registers[decoded_rd_address] <= lsu_out;
						MUX_CONSTANT: registers[decoded_rd_address] <= immediate_extended;
						MUX_FMA: registers[decoded_rd_address] <= fma_out;
						MUX_ACT: registers[decoded_rd_address] <= act_out;
						default: registers[decoded_rd_address] <= alu_out;
					endcase
			end
		end
endmodule
`default_nettype none
module scheduler (
	clk,
	reset,
	start,
	decoded_mem_read_enable,
	decoded_mem_write_enable,
	decoded_fma_enable,
	decoded_ret,
	fetcher_state,
	lsu_state,
	current_pc,
	next_pc,
	core_state,
	done
);
	parameter THREADS_PER_BLOCK = 4;
	parameter PROGRAM_MEM_ADDR_BITS = 8;
	input wire clk;
	input wire reset;
	input wire start;
	input wire decoded_mem_read_enable;
	input wire decoded_mem_write_enable;
	input wire decoded_fma_enable;
	input wire decoded_ret;
	input wire [2:0] fetcher_state;
	input wire [(THREADS_PER_BLOCK * 2) - 1:0] lsu_state;
	output reg [PROGRAM_MEM_ADDR_BITS - 1:0] current_pc;
	input wire [(THREADS_PER_BLOCK * PROGRAM_MEM_ADDR_BITS) - 1:0] next_pc;
	output reg [2:0] core_state;
	output reg done;
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
	always @(*) begin
		any_lsu_waiting = 1'b0;
		for (i = 0; i < THREADS_PER_BLOCK; i = i + 1)
			if ((lsu_state[i * 2+:2] == 2'b01) || (lsu_state[i * 2+:2] == 2'b10))
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
					else begin
						current_pc <= next_pc[(THREADS_PER_BLOCK - 1) * PROGRAM_MEM_ADDR_BITS+:PROGRAM_MEM_ADDR_BITS];
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
	buffer_select,
	swap_buffers,
	prefetch_en,
	prefetch_start_addr,
	prefetch_length,
	prefetch_done,
	bank_busy
);
	parameter DATA_BITS = 16;
	parameter ADDR_BITS = 12;
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
	input wire buffer_select;
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
	integer i;
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