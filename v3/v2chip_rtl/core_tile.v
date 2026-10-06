`default_nettype none
module core_tile (
	clk,
	reset,
	core_reset,
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
	data_mem_read_accept,
	data_mem_read_ready,
	data_mem_read_data,
	data_mem_write_valid,
	data_mem_write_address,
	data_mem_write_data,
	data_mem_write_ready
);
	parameter DATA_MEM_ADDR_BITS = 19;
	parameter DATA_MEM_DATA_BITS = 16;
	parameter PROGRAM_MEM_ADDR_BITS = 9;
	parameter PROGRAM_MEM_DATA_BITS = 16;
	parameter THREADS_PER_BLOCK = 8;
	parameter SYSTOLIC_SIZE = 8;
	parameter NUM_SYSTOLIC_ARRAYS = 1;
	parameter CACHE_SIZE = 2;
	parameter NUMBER_FORMAT = 0;
	input wire clk;
	input wire reset;
	input wire core_reset;
	input wire start;
	output wire done;
	input wire [7:0] block_id;
	input wire [$clog2(THREADS_PER_BLOCK):0] thread_count;
	output wire program_mem_read_valid;
	output wire [PROGRAM_MEM_ADDR_BITS - 1:0] program_mem_read_address;
	input wire program_mem_read_ready;
	input wire [PROGRAM_MEM_DATA_BITS - 1:0] program_mem_read_data;
	output wire data_mem_read_valid;
	output wire [DATA_MEM_ADDR_BITS - 1:0] data_mem_read_address;
	input wire data_mem_read_accept;
	input wire data_mem_read_ready;
	input wire [DATA_MEM_DATA_BITS - 1:0] data_mem_read_data;
	output wire data_mem_write_valid;
	output wire [DATA_MEM_ADDR_BITS - 1:0] data_mem_write_address;
	output wire [DATA_MEM_DATA_BITS - 1:0] data_mem_write_data;
	input wire data_mem_write_ready;
	wire [2:0] core_state_for_decode;
	wire [15:0] core_instruction;
	wire [3:0] decoded_rd_address;
	wire [3:0] decoded_rs_address;
	wire [3:0] decoded_rt_address;
	wire [2:0] decoded_nzp;
	wire [7:0] decoded_immediate;
	wire decoded_reg_write_enable;
	wire decoded_mem_read_enable;
	wire decoded_mem_pair;
	wire decoded_mem_write_enable;
	wire decoded_nzp_write_enable;
	wire [2:0] decoded_reg_input_mux;
	wire [2:0] decoded_alu_arithmetic_mux;
	wire decoded_alu_output_mux;
	wire decoded_pc_mux;
	wire decoded_fma_enable;
	wire decoded_act_enable;
	wire [1:0] decoded_act_func;
	wire decoded_systolic_enable;
	wire [1:0] decoded_systolic_op;
	wire decoded_systolic_idx;
	wire decoded_systolic_bcast;
	wire decoded_branch;
	wire decoded_ret;
	decoder decoder_instance(
		.clk(clk),
		.reset(reset),
		.core_state(core_state_for_decode),
		.instruction(core_instruction),
		.decoded_rd_address(decoded_rd_address),
		.decoded_rs_address(decoded_rs_address),
		.decoded_rt_address(decoded_rt_address),
		.decoded_nzp(decoded_nzp),
		.decoded_immediate(decoded_immediate),
		.decoded_reg_write_enable(decoded_reg_write_enable),
		.decoded_mem_read_enable(decoded_mem_read_enable),
		.decoded_mem_pair(decoded_mem_pair),
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
		.decoded_systolic_bcast(decoded_systolic_bcast),
		.decoded_branch(decoded_branch),
		.decoded_ret(decoded_ret)
	);
	localparam LSUS = 2 * THREADS_PER_BLOCK;
	wire [LSUS - 1:0] lsu_read_valid;
	wire [(DATA_MEM_ADDR_BITS * LSUS) - 1:0] lsu_read_address_flat;
	wire [LSUS - 1:0] lsu_read_ready;
	wire [(DATA_MEM_DATA_BITS * LSUS) - 1:0] lsu_read_data_flat;
	wire [LSUS - 1:0] lsu_write_valid;
	wire [(DATA_MEM_ADDR_BITS * LSUS) - 1:0] lsu_write_address_flat;
	wire [(DATA_MEM_DATA_BITS * LSUS) - 1:0] lsu_write_data_flat;
	wire [LSUS - 1:0] lsu_write_ready;
	core #(
		.DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
		.DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
		.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
		.PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
		.THREADS_PER_BLOCK(THREADS_PER_BLOCK),
		.SYSTOLIC_SIZE(SYSTOLIC_SIZE),
		.NUM_SYSTOLIC_ARRAYS(NUM_SYSTOLIC_ARRAYS),
		.CACHE_SIZE(CACHE_SIZE),
		.NUMBER_FORMAT(NUMBER_FORMAT),
		.RESET_STAGE(1)
	) core_instance(
		.clk(clk),
		.reset(core_reset),
		.start(start),
		.done(done),
		.block_id(block_id),
		.thread_count(thread_count),
		.core_state_for_decode(core_state_for_decode),
		.instruction_for_decode(core_instruction),
		.decoded_rd_address(decoded_rd_address),
		.decoded_rs_address(decoded_rs_address),
		.decoded_rt_address(decoded_rt_address),
		.decoded_nzp(decoded_nzp),
		.decoded_immediate(decoded_immediate),
		.decoded_reg_write_enable(decoded_reg_write_enable),
		.decoded_mem_read_enable(decoded_mem_read_enable),
		.decoded_mem_pair(decoded_mem_pair),
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
		.decoded_systolic_bcast(decoded_systolic_bcast),
		.decoded_branch(decoded_branch),
		.decoded_ret(decoded_ret),
		.program_mem_read_valid(program_mem_read_valid),
		.program_mem_read_address(program_mem_read_address),
		.program_mem_read_ready(program_mem_read_ready),
		.program_mem_read_data(program_mem_read_data),
		.data_mem_read_valid(lsu_read_valid),
		.data_mem_read_address_flat(lsu_read_address_flat),
		.data_mem_read_ready(lsu_read_ready),
		.data_mem_read_data_flat(lsu_read_data_flat),
		.data_mem_write_valid(lsu_write_valid),
		.data_mem_write_address_flat(lsu_write_address_flat),
		.data_mem_write_data_flat(lsu_write_data_flat),
		.data_mem_write_ready(lsu_write_ready)
	);
	wire [LSUS - 1:0] miss_read_valid;
	wire [(DATA_MEM_ADDR_BITS * LSUS) - 1:0] miss_read_address_flat;
	wire [LSUS - 1:0] miss_read_ready;
	wire [(DATA_MEM_DATA_BITS * LSUS) - 1:0] miss_read_data_flat;
	wire [LSUS - 1:0] miss_write_valid;
	wire [(DATA_MEM_ADDR_BITS * LSUS) - 1:0] miss_write_address_flat;
	wire [(DATA_MEM_DATA_BITS * LSUS) - 1:0] miss_write_data_flat;
	wire [LSUS - 1:0] miss_write_ready;
	wire scratch_ram_en;
	wire [3:0] scratch_ram_we;
	wire [4:0] scratch_ram_addr;
	wire [31:0] scratch_ram_di;
	wire [31:0] scratch_ram_do;
	scratchpad #(
		.ADDR_BITS(DATA_MEM_ADDR_BITS),
		.DATA_BITS(DATA_MEM_DATA_BITS),
		.NUM_PORTS(LSUS)
	) data_scratchpad(
		.clk(clk),
		.reset(reset),
		.consumer_read_valid(lsu_read_valid),
		.consumer_read_address_flat(lsu_read_address_flat),
		.consumer_read_ready(lsu_read_ready),
		.consumer_read_data_flat(lsu_read_data_flat),
		.consumer_write_valid(lsu_write_valid),
		.consumer_write_address_flat(lsu_write_address_flat),
		.consumer_write_data_flat(lsu_write_data_flat),
		.consumer_write_ready(lsu_write_ready),
		.mem_read_valid(miss_read_valid),
		.mem_read_address_flat(miss_read_address_flat),
		.mem_read_ready(miss_read_ready),
		.mem_read_data_flat(miss_read_data_flat),
		.mem_write_valid(miss_write_valid),
		.mem_write_address_flat(miss_write_address_flat),
		.mem_write_data_flat(miss_write_data_flat),
		.mem_write_ready(miss_write_ready),
		.ram_en(scratch_ram_en),
		.ram_we(scratch_ram_we),
		.ram_addr(scratch_ram_addr),
		.ram_di(scratch_ram_di),
		.ram_do(scratch_ram_do)
	);
	RAM32 scratch_ram(
		.CLK(clk),
		.EN0(scratch_ram_en),
		.WE0(scratch_ram_we),
		.A0(scratch_ram_addr),
		.Di0(scratch_ram_di),
		.Do0(scratch_ram_do)
	);
	tile_mem_queue #(
		.ADDR_BITS(DATA_MEM_ADDR_BITS),
		.DATA_BITS(DATA_MEM_DATA_BITS),
		.NUM_CONSUMERS(LSUS)
	) data_mem_queue(
		.clk(clk),
		.reset(reset),
		.consumer_read_valid(miss_read_valid),
		.consumer_read_address_flat(miss_read_address_flat),
		.consumer_read_ready(miss_read_ready),
		.consumer_read_data_flat(miss_read_data_flat),
		.consumer_write_valid(miss_write_valid),
		.consumer_write_address_flat(miss_write_address_flat),
		.consumer_write_data_flat(miss_write_data_flat),
		.consumer_write_ready(miss_write_ready),
		.mem_read_valid(data_mem_read_valid),
		.mem_read_address(data_mem_read_address),
		.mem_read_accept(data_mem_read_accept),
		.mem_read_ready(data_mem_read_ready),
		.mem_read_data(data_mem_read_data),
		.mem_write_valid(data_mem_write_valid),
		.mem_write_address(data_mem_write_address),
		.mem_write_data(data_mem_write_data),
		.mem_write_accept(data_mem_write_ready)
	);
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
	decoded_mem_pair,
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
	decoded_systolic_bcast,
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
	parameter THREADS_PER_BLOCK = 8;
	parameter SYSTOLIC_SIZE = 8;
	parameter NUM_SYSTOLIC_ARRAYS = 1;
	parameter CACHE_SIZE = 2;
	parameter NUMBER_FORMAT = 0;
	parameter RESET_STAGE = 0;
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
	input wire decoded_mem_pair;
	input wire decoded_mem_write_enable;
	input wire decoded_nzp_write_enable;
	input wire [2:0] decoded_reg_input_mux;
	input wire [2:0] decoded_alu_arithmetic_mux;
	input wire decoded_alu_output_mux;
	input wire decoded_pc_mux;
	input wire decoded_fma_enable;
	input wire decoded_act_enable;
	input wire [1:0] decoded_act_func;
	input wire decoded_systolic_enable;
	input wire [1:0] decoded_systolic_op;
	input wire decoded_systolic_idx;
	input wire decoded_systolic_bcast;
	input wire decoded_branch;
	input wire decoded_ret;
	output wire program_mem_read_valid;
	output wire [PROGRAM_MEM_ADDR_BITS - 1:0] program_mem_read_address;
	input wire program_mem_read_ready;
	input wire [PROGRAM_MEM_DATA_BITS - 1:0] program_mem_read_data;
	output wire [(2 * THREADS_PER_BLOCK) - 1:0] data_mem_read_valid;
	output wire [((DATA_MEM_ADDR_BITS * 2) * THREADS_PER_BLOCK) - 1:0] data_mem_read_address_flat;
	input wire [(2 * THREADS_PER_BLOCK) - 1:0] data_mem_read_ready;
	input wire [((DATA_MEM_DATA_BITS * 2) * THREADS_PER_BLOCK) - 1:0] data_mem_read_data_flat;
	output wire [(2 * THREADS_PER_BLOCK) - 1:0] data_mem_write_valid;
	output wire [((DATA_MEM_ADDR_BITS * 2) * THREADS_PER_BLOCK) - 1:0] data_mem_write_address_flat;
	output wire [((DATA_MEM_DATA_BITS * 2) * THREADS_PER_BLOCK) - 1:0] data_mem_write_data_flat;
	input wire [(2 * THREADS_PER_BLOCK) - 1:0] data_mem_write_ready;
	localparam LSUS = 2 * THREADS_PER_BLOCK;
	wire [DATA_MEM_ADDR_BITS - 1:0] data_mem_read_address [LSUS - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] data_mem_read_data [LSUS - 1:0];
	wire [DATA_MEM_ADDR_BITS - 1:0] data_mem_write_address [LSUS - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] data_mem_write_data [LSUS - 1:0];
	genvar _gv_flat_idx_1;
	generate
		for (_gv_flat_idx_1 = 0; _gv_flat_idx_1 < LSUS; _gv_flat_idx_1 = _gv_flat_idx_1 + 1) begin : unflatten_mem
			localparam flat_idx = _gv_flat_idx_1;
			assign data_mem_read_data[flat_idx] = data_mem_read_data_flat[((flat_idx + 1) * DATA_MEM_DATA_BITS) - 1:flat_idx * DATA_MEM_DATA_BITS];
		end
	endgenerate
	genvar _gv_out_idx_1;
	generate
		for (_gv_out_idx_1 = 0; _gv_out_idx_1 < LSUS; _gv_out_idx_1 = _gv_out_idx_1 + 1) begin : flatten_out
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
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] update_pc;
	wire fetch_ahead_hit;
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] next_pc [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] rs [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] rt [THREADS_PER_BLOCK - 1:0];
	wire [1:0] lsu_state [LSUS - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] lsu_out [LSUS - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] alu_out [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] fma_out [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] act_out [THREADS_PER_BLOCK - 1:0];
	reg [DATA_MEM_DATA_BITS - 1:0] systolic_out [THREADS_PER_BLOCK - 1:0];
	reg [(2 * LSUS) - 1:0] lsu_state_flat;
	reg [(PROGRAM_MEM_ADDR_BITS * THREADS_PER_BLOCK) - 1:0] next_pc_flat;
	integer lsu_idx;
	always @(*) begin
		for (lsu_idx = 0; lsu_idx < LSUS; lsu_idx = lsu_idx + 1)
			lsu_state_flat[lsu_idx * 2+:2] = lsu_state[lsu_idx];
		for (lsu_idx = 0; lsu_idx < THREADS_PER_BLOCK; lsu_idx = lsu_idx + 1)
			next_pc_flat[lsu_idx * PROGRAM_MEM_ADDR_BITS+:PROGRAM_MEM_ADDR_BITS] = next_pc[lsu_idx];
	end
	wire [DATA_MEM_DATA_BITS - 1:0] rd_data [THREADS_PER_BLOCK - 1:0];
	wire unit_reset;
	generate
		if (RESET_STAGE) begin : g_reset_reg
			reg reset_q;
			always @(posedge clk) reset_q <= reset;
			assign unit_reset = reset_q;
		end
		else begin : g_reset_direct
			assign unit_reset = reset;
		end
	endgenerate
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
		.next_pc(update_pc),
		.ahead_hit(fetch_ahead_hit),
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
	reg pipe_mem_pair;
	reg pipe_mem_write_enable;
	reg pipe_nzp_write_enable;
	reg [2:0] pipe_reg_input_mux;
	reg [2:0] pipe_alu_arithmetic_mux;
	reg pipe_alu_output_mux;
	reg pipe_pc_mux;
	reg pipe_fma_enable;
	reg pipe_act_enable;
	reg [1:0] pipe_act_func;
	reg pipe_systolic_enable;
	reg [1:0] pipe_systolic_op;
	reg pipe_systolic_idx;
	reg pipe_systolic_bcast;
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
			pipe_mem_pair <= 1'b0;
			pipe_mem_write_enable <= 1'b0;
			pipe_nzp_write_enable <= 1'b0;
			pipe_reg_input_mux <= 3'b000;
			pipe_alu_arithmetic_mux <= 3'b000;
			pipe_alu_output_mux <= 1'b0;
			pipe_pc_mux <= 1'b0;
			pipe_fma_enable <= 1'b0;
			pipe_act_enable <= 1'b0;
			pipe_act_func <= 2'b00;
			pipe_systolic_enable <= 1'b0;
			pipe_systolic_op <= 2'b00;
			pipe_systolic_idx <= 1'b0;
			pipe_systolic_bcast <= 1'b0;
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
			pipe_mem_pair <= decoded_mem_pair;
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
			pipe_systolic_bcast <= decoded_systolic_bcast;
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
	localparam FP_UNITS = NUMBER_FORMAT != 0;
	wire decoded_staged = ((decoded_mem_read_enable | decoded_mem_write_enable) | decoded_fma_enable) | decoded_act_enable;
	wire sys_read_hold;
	wire [3:1] sv2v_tmp_scheduler_instance_core_state;
	always @(*) core_state = sv2v_tmp_scheduler_instance_core_state;
	wire [PROGRAM_MEM_ADDR_BITS:1] sv2v_tmp_scheduler_instance_current_pc;
	always @(*) current_pc = sv2v_tmp_scheduler_instance_current_pc;
	scheduler #(
		.THREADS_PER_BLOCK(THREADS_PER_BLOCK),
		.NUM_LSUS(LSUS),
		.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
		.ENABLE_BRANCH_DIVERGE(0)
	) scheduler_instance(
		.clk(clk),
		.reset(reset),
		.start(start),
		.fetcher_state(fetcher_state),
		.fetch_ahead_hit(fetch_ahead_hit),
		.update_pc(update_pc),
		.core_state(sv2v_tmp_scheduler_instance_core_state),
		.decoded_fma_enable(pipe_fma_enable),
		.decoded_staged(decoded_staged),
		.decoded_hold(sys_read_hold),
		.decoded_ret(pipe_ret),
		.decoded_branch(pipe_branch),
		.branch_taken(branch_taken),
		.branch_target(branch_target),
		.reconverge_pc(reconverge_pc),
		.lsu_state_flat(lsu_state_flat),
		.lsu_answer(data_mem_read_ready | data_mem_write_ready),
		.pipe_mem_op(pipe_mem_read_enable | pipe_mem_write_enable),
		.pipe_mem_pair(pipe_mem_pair),
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
		if (unit_reset) begin : sv2v_autoblock_1
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
				.reset(unit_reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.decoded_alu_arithmetic_mux(pipe_alu_arithmetic_mux),
				.decoded_alu_output_mux(pipe_alu_output_mux),
				.rs(pipe_rs[i]),
				.rt(pipe_rt[i]),
				.alu_out(alu_out[i])
			);
			if (NUMBER_FORMAT == 0) begin : g_sf16
				fma #(.DATA_BITS(DATA_MEM_DATA_BITS)) fma_instance(
					.clk(clk),
					.reset(unit_reset),
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
					.reset(unit_reset),
					.enable(i < thread_count),
					.core_state(core_state),
					.activation_enable(pipe_act_enable),
					.activation_func(pipe_act_func),
					.unbiased_activation(pipe_rs[i]),
					.bias(pipe_rt[i]),
					.activation_out(act_out[i])
				);
			end
			else begin : g_fp
				fp_fma #(
					.EXP_BITS((NUMBER_FORMAT == 2 ? 8 : 5)),
					.MANT_BITS((NUMBER_FORMAT == 2 ? 7 : 10)),
					.ALIGN_STAGE(1)
				) fma_instance(
					.clk(clk),
					.reset(unit_reset),
					.enable(i < thread_count),
					.core_state(core_state),
					.decoded_fma_enable(pipe_fma_enable),
					.rs(pipe_rs[i]),
					.rt(pipe_rt[i]),
					.rq(pipe_rd_data[i]),
					.fma_out(fma_out[i])
				);
				fp_activation #(
					.EXP_BITS((NUMBER_FORMAT == 2 ? 8 : 5)),
					.MANT_BITS((NUMBER_FORMAT == 2 ? 7 : 10)),
					.ALIGN_STAGE(1)
				) activation_instance(
					.clk(clk),
					.reset(unit_reset),
					.enable(i < thread_count),
					.core_state(core_state),
					.activation_enable(pipe_act_enable),
					.activation_func(pipe_act_func),
					.unbiased_activation(pipe_rs[i]),
					.bias(pipe_rt[i]),
					.activation_out(act_out[i])
				);
			end
			lsu #(
				.ADDR_BITS(DATA_MEM_ADDR_BITS),
				.DATA_BITS(DATA_MEM_DATA_BITS)
			) lsu_instance(
				.clk(clk),
				.reset(unit_reset),
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
			lsu #(
				.ADDR_BITS(DATA_MEM_ADDR_BITS),
				.DATA_BITS(DATA_MEM_DATA_BITS)
			) lsu_b_instance(
				.clk(clk),
				.reset(unit_reset),
				.enable(i < thread_count),
				.core_state(core_state),
				.decoded_mem_read_enable(pipe_mem_read_enable & pipe_mem_pair),
				.decoded_mem_write_enable(1'b0),
				.rs(pipe_rt[i]),
				.rt({DATA_MEM_DATA_BITS {1'b0}}),
				.mem_read_valid(data_mem_read_valid[THREADS_PER_BLOCK + i]),
				.mem_read_address(data_mem_read_address[THREADS_PER_BLOCK + i]),
				.mem_read_ready(data_mem_read_ready[THREADS_PER_BLOCK + i]),
				.mem_read_data(data_mem_read_data[THREADS_PER_BLOCK + i]),
				.mem_write_valid(data_mem_write_valid[THREADS_PER_BLOCK + i]),
				.mem_write_address(data_mem_write_address[THREADS_PER_BLOCK + i]),
				.mem_write_data(data_mem_write_data[THREADS_PER_BLOCK + i]),
				.mem_write_ready(data_mem_write_ready[THREADS_PER_BLOCK + i]),
				.lsu_state(lsu_state[THREADS_PER_BLOCK + i]),
				.lsu_out(lsu_out[THREADS_PER_BLOCK + i])
			);
			registers #(
				.THREADS_PER_BLOCK(THREADS_PER_BLOCK),
				.THREAD_ID(i),
				.DATA_BITS(DATA_MEM_DATA_BITS)
			) register_instance(
				.clk(clk),
				.reset(unit_reset),
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
				.pair_write(pipe_mem_pair),
				.lsu_pair_out(lsu_out[THREADS_PER_BLOCK + i]),
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
				.reset(unit_reset),
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
	localparam [31:0] SYSTOLIC_RESULT_COUNT = SYSTOLIC_SIZE * SYSTOLIC_SIZE;
	localparam [31:0] CELL_BITS = $clog2(SYSTOLIC_RESULT_COUNT);
	wire systolic_exec = (core_state == 3'b101) && pipe_systolic_enable;
	wire systolic_clear_acc = systolic_exec && (pipe_systolic_op == SYSTOLIC_OP_CLEAR);
	wire systolic_load_weights = systolic_exec && (pipe_systolic_op == SYSTOLIC_OP_LOAD);
	wire systolic_compute_enable = systolic_exec && (pipe_systolic_op == SYSTOLIC_OP_COMPUTE);
	localparam [2:0] SYS_LAT = (FP_UNITS ? 3'd6 : 3'd4);
	reg [2:0] sys_cnt;
	always @(posedge clk)
		if (unit_reset)
			sys_cnt <= 3'd0;
		else if (systolic_compute_enable)
			sys_cnt <= SYS_LAT - 3'd1;
		else if (sys_cnt != 3'd0)
			sys_cnt <= sys_cnt - 3'd1;
	assign sys_read_hold = (decoded_systolic_enable && (decoded_systolic_op == 2'b11)) && (sys_cnt > 3'd1);
	wire [(DATA_MEM_DATA_BITS * SYSTOLIC_SIZE) - 1:0] systolic_a_inputs_flat [NUM_SYSTOLIC_ARRAYS - 1:0];
	wire [(DATA_MEM_DATA_BITS * SYSTOLIC_SIZE) - 1:0] systolic_b_inputs_flat [NUM_SYSTOLIC_ARRAYS - 1:0];
	wire [(DATA_MEM_DATA_BITS * SYSTOLIC_RESULT_COUNT) - 1:0] systolic_results_flat [NUM_SYSTOLIC_ARRAYS - 1:0];
	wire [NUM_SYSTOLIC_ARRAYS - 1:0] systolic_ready;
	wire systolic_operand_update = (systolic_clear_acc || systolic_load_weights) || systolic_compute_enable;
	reg [DATA_MEM_DATA_BITS - 1:0] sys_a_hold [THREADS_PER_BLOCK - 1:0];
	reg [DATA_MEM_DATA_BITS - 1:0] sys_b_hold [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] sys_a [THREADS_PER_BLOCK - 1:0];
	wire [DATA_MEM_DATA_BITS - 1:0] sys_b [THREADS_PER_BLOCK - 1:0];
	genvar _gv_hold_idx_1;
	generate
		for (_gv_hold_idx_1 = 0; _gv_hold_idx_1 < THREADS_PER_BLOCK; _gv_hold_idx_1 = _gv_hold_idx_1 + 1) begin : sys_operand_hold
			localparam hold_idx = _gv_hold_idx_1;
			always @(posedge clk)
				if (unit_reset) begin
					sys_a_hold[hold_idx] <= {DATA_MEM_DATA_BITS {1'b0}};
					sys_b_hold[hold_idx] <= {DATA_MEM_DATA_BITS {1'b0}};
				end
				else if (systolic_operand_update) begin
					sys_a_hold[hold_idx] <= pipe_rs[hold_idx];
					sys_b_hold[hold_idx] <= pipe_rt[hold_idx];
				end
			assign sys_a[hold_idx] = (systolic_operand_update ? pipe_rs[hold_idx] : sys_a_hold[hold_idx]);
			assign sys_b[hold_idx] = (systolic_operand_update ? pipe_rt[hold_idx] : sys_b_hold[hold_idx]);
		end
	endgenerate
	genvar _gv_arr_idx_1;
	genvar _gv_elem_idx_1;
	generate
		for (_gv_arr_idx_1 = 0; _gv_arr_idx_1 < NUM_SYSTOLIC_ARRAYS; _gv_arr_idx_1 = _gv_arr_idx_1 + 1) begin : input_map
			localparam arr_idx = _gv_arr_idx_1;
			for (_gv_elem_idx_1 = 0; _gv_elem_idx_1 < SYSTOLIC_SIZE; _gv_elem_idx_1 = _gv_elem_idx_1 + 1) begin : elem_map
				localparam elem_idx = _gv_elem_idx_1;
				localparam signed [31:0] thread_idx = (arr_idx * SYSTOLIC_SIZE) + elem_idx;
				if (thread_idx < THREADS_PER_BLOCK) begin : active_thread
					assign systolic_a_inputs_flat[arr_idx][elem_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = sys_a[thread_idx];
					assign systolic_b_inputs_flat[arr_idx][elem_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = sys_b[thread_idx];
				end
				else begin : inactive_thread
					assign systolic_a_inputs_flat[arr_idx][elem_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = {DATA_MEM_DATA_BITS {1'b0}};
					assign systolic_b_inputs_flat[arr_idx][elem_idx * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS] = {DATA_MEM_DATA_BITS {1'b0}};
				end
			end
		end
	endgenerate
	reg [DATA_MEM_DATA_BITS - 1:0] systolic_sel_q [THREADS_PER_BLOCK - 1:0];
	integer systolic_thread_idx;
	always @(posedge clk)
		for (systolic_thread_idx = 0; systolic_thread_idx < THREADS_PER_BLOCK; systolic_thread_idx = systolic_thread_idx + 1)
			if (unit_reset || !(pipe_systolic_idx < NUM_SYSTOLIC_ARRAYS))
				systolic_sel_q[systolic_thread_idx] <= {DATA_MEM_DATA_BITS {1'b0}};
			else
				systolic_sel_q[systolic_thread_idx] <= systolic_results_flat[pipe_systolic_idx][pipe_rs[systolic_thread_idx][CELL_BITS - 1:0] * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS];
	integer systolic_conv_idx;
	function automatic [((DATA_MEM_DATA_BITS - 2) >= 0 ? DATA_MEM_DATA_BITS - 1 : 3 - DATA_MEM_DATA_BITS) - 1:0] sv2v_cast_161F1;
		input reg [((DATA_MEM_DATA_BITS - 2) >= 0 ? DATA_MEM_DATA_BITS - 1 : 3 - DATA_MEM_DATA_BITS) - 1:0] inp;
		sv2v_cast_161F1 = inp;
	endfunction
	always @(*)
		for (systolic_conv_idx = 0; systolic_conv_idx < THREADS_PER_BLOCK; systolic_conv_idx = systolic_conv_idx + 1)
			if (NUMBER_FORMAT == 0)
				systolic_out[systolic_conv_idx] = (systolic_sel_q[systolic_conv_idx][DATA_MEM_DATA_BITS - 1] ? {1'b1, sv2v_cast_161F1(-systolic_sel_q[systolic_conv_idx])} : systolic_sel_q[systolic_conv_idx]);
			else
				systolic_out[systolic_conv_idx] = systolic_sel_q[systolic_conv_idx];
	genvar _gv_k_1;
	generate
		for (_gv_k_1 = 0; _gv_k_1 < NUM_SYSTOLIC_ARRAYS; _gv_k_1 = _gv_k_1 + 1) begin : systolic_arrays
			localparam k = _gv_k_1;
			systolic_array #(
				.DATA_BITS(DATA_MEM_DATA_BITS),
				.ARRAY_SIZE(SYSTOLIC_SIZE),
				.PIPE_INTERVAL(SYSTOLIC_SIZE),
				.NUMBER_FORMAT(NUMBER_FORMAT)
			) systolic_array_inst(
				.clk(clk),
				.reset(unit_reset),
				.clear_acc(systolic_clear_acc),
				.load_weights(systolic_load_weights),
				.load_broadcast(pipe_systolic_bcast),
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
	decoded_mem_pair,
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
	decoded_systolic_bcast,
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
	output reg decoded_mem_pair;
	output reg decoded_mem_write_enable;
	output reg decoded_nzp_write_enable;
	output reg [2:0] decoded_reg_input_mux;
	output reg [2:0] decoded_alu_arithmetic_mux;
	output reg decoded_alu_output_mux;
	output reg decoded_pc_mux;
	output reg decoded_fma_enable;
	output reg decoded_act_enable;
	output reg [1:0] decoded_act_func;
	output reg decoded_systolic_enable;
	output reg [1:0] decoded_systolic_op;
	output reg decoded_systolic_idx;
	output reg decoded_systolic_bcast;
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
	localparam SH = 4'b1101;
	localparam CONSTH = 4'b1110;
	localparam RET = 4'b1111;
	always @(*) begin
		decoded_rd_address = instruction[11:8];
		decoded_rs_address = instruction[7:4];
		decoded_rt_address = instruction[3:0];
		decoded_immediate = instruction[7:0];
		decoded_nzp = instruction[11:9];
		decoded_reg_write_enable = 0;
		decoded_mem_read_enable = 0;
		decoded_mem_pair = 0;
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
		decoded_systolic_bcast = 0;
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
				decoded_alu_arithmetic_mux = 3'b000;
			end
			SUB: begin
				decoded_reg_write_enable = 1;
				decoded_reg_input_mux = 3'b000;
				decoded_alu_arithmetic_mux = 3'b001;
			end
			MUL: begin
				decoded_reg_write_enable = 1;
				decoded_reg_input_mux = 3'b000;
				decoded_alu_arithmetic_mux = 3'b010;
			end
			DIV: begin
				decoded_reg_write_enable = 1;
				decoded_reg_input_mux = 3'b000;
				decoded_alu_arithmetic_mux = 3'b011;
			end
			SH: begin
				decoded_reg_write_enable = 1;
				decoded_reg_input_mux = 3'b000;
				decoded_alu_arithmetic_mux = 3'b100;
			end
			CONSTH: begin
				decoded_reg_write_enable = 1;
				decoded_reg_input_mux = 3'b110;
			end
			LDR: begin
				decoded_reg_write_enable = 1;
				decoded_reg_input_mux = 3'b001;
				decoded_mem_read_enable = 1;
				decoded_mem_pair = instruction[3:0] != 4'd0;
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
				decoded_systolic_bcast = (instruction[7:6] == 2'b01) & instruction[5];
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
module fetcher (
	clk,
	reset,
	core_state,
	current_pc,
	next_pc,
	ahead_hit,
	mem_read_valid,
	mem_read_address,
	mem_read_ready,
	mem_read_data,
	fetcher_state,
	instruction
);
	parameter PROGRAM_MEM_ADDR_BITS = 8;
	parameter PROGRAM_MEM_DATA_BITS = 16;
	parameter L0_ENTRIES = 32;
	input wire clk;
	input wire reset;
	input wire [2:0] core_state;
	input wire [PROGRAM_MEM_ADDR_BITS - 1:0] current_pc;
	input wire [PROGRAM_MEM_ADDR_BITS - 1:0] next_pc;
	output wire ahead_hit;
	output reg mem_read_valid;
	output reg [PROGRAM_MEM_ADDR_BITS - 1:0] mem_read_address;
	input wire mem_read_ready;
	input wire [PROGRAM_MEM_DATA_BITS - 1:0] mem_read_data;
	output reg [2:0] fetcher_state;
	output reg [PROGRAM_MEM_DATA_BITS - 1:0] instruction;
	localparam IDLE = 3'b000;
	localparam FETCHING = 3'b001;
	localparam FETCHED = 3'b010;
	localparam IDX_BITS = (L0_ENTRIES > 1 ? $clog2(L0_ENTRIES) : 1);
	localparam TAG_BITS = PROGRAM_MEM_ADDR_BITS - IDX_BITS;
	wire l0_hit;
	wire [PROGRAM_MEM_DATA_BITS - 1:0] l0_word;
	generate
		if (L0_ENTRIES > 0) begin : g_l0
			reg [PROGRAM_MEM_DATA_BITS - 1:0] l0_data [L0_ENTRIES - 1:0];
			reg [TAG_BITS - 1:0] l0_tag [L0_ENTRIES - 1:0];
			reg [L0_ENTRIES - 1:0] l0_valid;
			wire [PROGRAM_MEM_ADDR_BITS - 1:0] lpc = (core_state == 3'b110 ? next_pc : current_pc);
			wire [IDX_BITS - 1:0] idx = lpc[IDX_BITS - 1:0];
			wire [IDX_BITS - 1:0] fidx = mem_read_address[IDX_BITS - 1:0];
			assign l0_hit = l0_valid[idx] && (l0_tag[idx] == lpc[PROGRAM_MEM_ADDR_BITS - 1:IDX_BITS]);
			assign l0_word = l0_data[idx];
			always @(posedge clk)
				if (reset)
					l0_valid <= {L0_ENTRIES {1'b0}};
				else if ((fetcher_state == FETCHING) && mem_read_ready) begin
					l0_valid[fidx] <= 1'b1;
					l0_tag[fidx] <= mem_read_address[PROGRAM_MEM_ADDR_BITS - 1:IDX_BITS];
					l0_data[fidx] <= mem_read_data;
				end
		end
		else begin : g_no_l0
			assign l0_hit = 1'b0;
			assign l0_word = {PROGRAM_MEM_DATA_BITS {1'b0}};
		end
	endgenerate
	assign ahead_hit = ((core_state == 3'b110) && (fetcher_state == IDLE)) && l0_hit;
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
					if (ahead_hit) begin
						instruction <= l0_word;
						fetcher_state <= FETCHED;
					end
					else if (core_state == 3'b001) begin
						if (l0_hit) begin
							instruction <= l0_word;
							fetcher_state <= FETCHED;
						end
						else begin
							fetcher_state <= FETCHING;
							mem_read_valid <= 1;
							mem_read_address <= current_pc;
						end
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
`default_nettype wire
`default_nettype none
module scheduler (
	clk,
	reset,
	start,
	decoded_fma_enable,
	decoded_staged,
	decoded_hold,
	decoded_ret,
	decoded_branch,
	branch_taken,
	branch_target,
	reconverge_pc,
	fetcher_state,
	fetch_ahead_hit,
	lsu_state_flat,
	lsu_answer,
	pipe_mem_op,
	pipe_mem_pair,
	current_pc,
	update_pc,
	next_pc_flat,
	active_mask,
	diverged,
	core_state,
	done
);
	parameter THREADS_PER_BLOCK = 4;
	parameter NUM_LSUS = THREADS_PER_BLOCK;
	parameter PROGRAM_MEM_ADDR_BITS = 8;
	parameter ENABLE_BRANCH_DIVERGE = 0;
	input wire clk;
	input wire reset;
	input wire start;
	input wire decoded_fma_enable;
	input wire decoded_staged;
	input wire decoded_hold;
	input wire decoded_ret;
	input wire decoded_branch;
	input wire [THREADS_PER_BLOCK - 1:0] branch_taken;
	input wire [PROGRAM_MEM_ADDR_BITS - 1:0] branch_target;
	input wire [PROGRAM_MEM_ADDR_BITS - 1:0] reconverge_pc;
	input wire [2:0] fetcher_state;
	input wire fetch_ahead_hit;
	input wire [(2 * NUM_LSUS) - 1:0] lsu_state_flat;
	input wire [NUM_LSUS - 1:0] lsu_answer;
	input wire pipe_mem_op;
	input wire pipe_mem_pair;
	output reg [PROGRAM_MEM_ADDR_BITS - 1:0] current_pc;
	output wire [PROGRAM_MEM_ADDR_BITS - 1:0] update_pc;
	input wire [(PROGRAM_MEM_ADDR_BITS * THREADS_PER_BLOCK) - 1:0] next_pc_flat;
	output wire [THREADS_PER_BLOCK - 1:0] active_mask;
	output wire diverged;
	output reg [2:0] core_state;
	output reg done;
	wire [1:0] lsu_state [NUM_LSUS - 1:0];
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] next_pc [THREADS_PER_BLOCK - 1:0];
	genvar _gv_sch_idx_1;
	generate
		for (_gv_sch_idx_1 = 0; _gv_sch_idx_1 < NUM_LSUS; _gv_sch_idx_1 = _gv_sch_idx_1 + 1) begin : unflatten_lsu
			localparam sch_idx = _gv_sch_idx_1;
			assign lsu_state[sch_idx] = lsu_state_flat[((sch_idx + 1) * 2) - 1:sch_idx * 2];
		end
		for (_gv_sch_idx_1 = 0; _gv_sch_idx_1 < THREADS_PER_BLOCK; _gv_sch_idx_1 = _gv_sch_idx_1 + 1) begin : unflatten_sch
			localparam sch_idx = _gv_sch_idx_1;
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
	reg lsus_done_next;
	integer i;
	reg fma_execute_second_cycle;
	wire [PROGRAM_MEM_ADDR_BITS - 1:0] diverge_next_pc;
	wire diverge_stall;
	generate
		if (ENABLE_BRANCH_DIVERGE) begin : gen_branch_diverge
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
		end
		else begin : gen_no_diverge
			assign active_mask = {THREADS_PER_BLOCK {1'b1}};
			assign diverged = 1'b0;
			assign diverge_stall = 1'b0;
			assign diverge_next_pc = {PROGRAM_MEM_ADDR_BITS {1'b0}};
		end
	endgenerate
	assign update_pc = (diverged ? diverge_next_pc : next_pc[0]);
	always @(*) begin
		any_lsu_waiting = 1'b0;
		lsus_done_next = 1'b1;
		for (i = 0; i < NUM_LSUS; i = i + 1)
			if ((lsu_state[i] == 2'b01) || (lsu_state[i] == 2'b10)) begin
				any_lsu_waiting = 1'b1;
				if (!lsu_answer[i])
					lsus_done_next = 1'b0;
			end
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
				DECODE: begin
					if (!decoded_hold)
						core_state <= (decoded_staged ? REQUEST : EXECUTE);
					fma_execute_second_cycle <= 1'b0;
				end
				REQUEST: core_state <= WAIT;
				WAIT:
					if (lsus_done_next) begin
						core_state <= (pipe_mem_op && !pipe_mem_pair ? UPDATE : EXECUTE);
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
						current_pc <= update_pc;
						core_state <= (fetch_ahead_hit ? DECODE : FETCH);
					end
				DONE:
					;
			endcase
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
	input wire [2:0] decoded_alu_arithmetic_mux;
	input wire decoded_alu_output_mux;
	input wire [DATA_BITS - 1:0] rs;
	input wire [DATA_BITS - 1:0] rt;
	output wire [DATA_BITS - 1:0] alu_out;
	localparam ADD = 3'b000;
	localparam SUB = 3'b001;
	localparam MUL = 3'b010;
	localparam DIV = 3'b011;
	localparam SH = 3'b100;
	reg [DATA_BITS - 1:0] alu_out_reg;
	assign alu_out = alu_out_reg;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
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
						MUL: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, rs[7:0]} * {{DATA_BITS - 8 {1'b0}}, rt[7:0]};
						DIV:
							case (rt[7:0])
								8'd1: alu_out_reg <= rs;
								8'd2: alu_out_reg <= rs >> 1;
								8'd3: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, sv2v_cast_8((sv2v_cast_32(rs[7:0]) * 32'd21846) >> 16)};
								8'd4: alu_out_reg <= rs >> 2;
								8'd8: alu_out_reg <= rs >> 3;
								8'd9: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, sv2v_cast_8((sv2v_cast_32(rs[7:0]) * 32'd7282) >> 16)};
								8'd10: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, sv2v_cast_8((sv2v_cast_32(rs[7:0]) * 32'd6554) >> 16)};
								8'd11: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, sv2v_cast_8((sv2v_cast_32(rs[7:0]) * 32'd5958) >> 16)};
								8'd12: alu_out_reg <= {{DATA_BITS - 8 {1'b0}}, sv2v_cast_8((sv2v_cast_32(rs[7:0]) * 32'd5462) >> 16)};
								8'd16: alu_out_reg <= rs >> 4;
								8'd32: alu_out_reg <= rs >> 5;
								8'd64: alu_out_reg <= rs >> 6;
								default: alu_out_reg <= {DATA_BITS {1'b0}};
							endcase
						SH: alu_out_reg <= (rt[4] ? rs >> (5'd0 - rt[4:0]) : rs << rt[3:0]);
						default: alu_out_reg <= {DATA_BITS {1'b0}};
					endcase
			end
		end
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
	reg [DATA_BITS - 1:0] fma_out_reg;
	assign fma_out = fma_out_reg;
	wire sign_r1 = rs[15];
	wire sign_r2 = rt[15];
	wire sign_product = sign_r1 ^ sign_r2;
	wire [14:0] mag_r1 = rs[14:0];
	wire [14:0] mag_r2 = rt[14:0];
	reg [21:0] partial_hi;
	reg [22:0] partial_lo;
	reg partial_sign;
	always @(posedge clk)
		if (reset) begin
			partial_hi <= 22'b0000000000000000000000;
			partial_lo <= 23'b00000000000000000000000;
			partial_sign <= 1'b0;
		end
		else begin
			partial_hi <= mag_r1 * mag_r2[14:8];
			partial_lo <= mag_r1 * mag_r2[7:0];
			partial_sign <= sign_product;
		end
	wire [29:0] product_unsigned = {partial_hi, 8'b00000000} + {7'b0000000, partial_lo};
	reg [14:0] product_mag;
	reg product_sign;
	always @(posedge clk)
		if (reset) begin
			product_mag <= 15'b000000000000000;
			product_sign <= 1'b0;
		end
		else begin
			product_mag <= product_unsigned[29:15];
			product_sign <= partial_sign;
		end
	wire [DATA_BITS - 1:0] product_sm = {product_sign, product_mag};
	wire [DATA_BITS - 1:0] product_saturated = (product_mag == 15'b000000000000000 ? {DATA_BITS {1'b0}} : product_sm);
	wire S_A = rq[15];
	wire [14:0] M_A = rq[14:0];
	wire S_B = product_saturated[15];
	wire [14:0] M_B = product_saturated[14:0];
	wire [15:0] sum_M = M_A + M_B;
	wire [15:0] diff_A_B = M_A - M_B;
	wire [15:0] diff_B_A = M_B - M_A;
	wire signs_equal = S_A == S_B;
	wire A_gte_B = M_A >= M_B;
	reg [15:0] sum_M_q;
	reg [15:0] diff_A_B_q;
	reg [15:0] diff_B_A_q;
	reg signs_equal_q;
	reg A_gte_B_q;
	reg S_A_q;
	reg S_B_q;
	wire res_S = (signs_equal_q ? S_A_q : (A_gte_B_q ? S_A_q : S_B_q));
	wire [14:0] res_M = (signs_equal_q ? (sum_M_q > 15'd32767 ? 15'd32767 : sum_M_q[14:0]) : (A_gte_B_q ? diff_A_B_q[14:0] : diff_B_A_q[14:0]));
	wire [DATA_BITS - 1:0] accumulated_saturated = (res_M == 15'b000000000000000 ? {DATA_BITS {1'b0}} : {res_S, res_M});
	reg exec_phase;
	always @(posedge clk)
		if (reset) begin
			fma_out_reg <= {DATA_BITS {1'b0}};
			exec_phase <= 1'b0;
		end
		else if (enable) begin
			if ((core_state != 3'b101) || !decoded_fma_enable)
				exec_phase <= 1'b0;
			if ((core_state == 3'b101) && decoded_fma_enable) begin
				if (!exec_phase) begin
					sum_M_q <= sum_M;
					diff_A_B_q <= diff_A_B;
					diff_B_A_q <= diff_B_A;
					signs_equal_q <= signs_equal;
					A_gte_B_q <= A_gte_B;
					S_A_q <= S_A;
					S_B_q <= S_B;
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
	wire S_A = unbiased_activation[15];
	wire [14:0] M_A = unbiased_activation[14:0];
	wire S_B = bias[15];
	wire [14:0] M_B = bias[14:0];
	wire [15:0] sum_M = M_A + M_B;
	wire [15:0] diff_A_B = M_A - M_B;
	wire [15:0] diff_B_A = M_B - M_A;
	wire signs_equal = S_A == S_B;
	wire A_gte_B = M_A >= M_B;
	reg [15:0] sum_M_q;
	reg [15:0] diff_A_B_q;
	reg [15:0] diff_B_A_q;
	reg signs_equal_q;
	reg A_gte_B_q;
	reg S_A_q;
	reg S_B_q;
	always @(posedge clk) begin
		sum_M_q <= sum_M;
		diff_A_B_q <= diff_A_B;
		diff_B_A_q <= diff_B_A;
		signs_equal_q <= signs_equal;
		A_gte_B_q <= A_gte_B;
		S_A_q <= S_A;
		S_B_q <= S_B;
	end
	wire res_S = (signs_equal_q ? S_A_q : (A_gte_B_q ? S_A_q : S_B_q));
	wire [14:0] res_M = (signs_equal_q ? (sum_M_q > 15'd32767 ? 15'd32767 : sum_M_q[14:0]) : (A_gte_B_q ? diff_A_B_q[14:0] : diff_B_A_q[14:0]));
	wire [DATA_BITS - 1:0] biased_sum = (res_M == 15'b000000000000000 ? {DATA_BITS {1'b0}} : {res_S, res_M});
	reg [DATA_BITS - 1:0] biased_q;
	always @(posedge clk) biased_q <= biased_sum;
	wire [DATA_BITS - 1:0] biased_activation = biased_q;
	wire is_negative = biased_activation[15];
	wire [14:0] leaky_mantissa = biased_activation[14:0] >> 7;
	wire [DATA_BITS - 1:0] leaky_value = (leaky_mantissa == 15'b000000000000000 ? Q115_ZERO : {1'b1, leaky_mantissa});
	wire [DATA_BITS - 1:0] relu_out = (is_negative ? Q115_ZERO : biased_activation);
	wire [DATA_BITS - 1:0] leaky_out = (is_negative ? leaky_value : biased_activation);
	wire [DATA_BITS - 1:0] activated_value = (activation_func == ACT_RELU ? relu_out : (activation_func == ACT_LEAKY_RELU ? leaky_out : (activation_func == ACT_CLIPPED_RELU ? relu_out : biased_activation)));
	always @(posedge clk)
		if (reset)
			activation_out_reg <= {DATA_BITS {1'b0}};
		else if (enable) begin
			if ((core_state == 3'b101) && activation_enable)
				activation_out_reg <= activated_value;
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
						if (core_state == 3'b011) begin
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
						if (core_state == 3'b011) begin
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
	pair_write,
	alu_out,
	lsu_out,
	lsu_pair_out,
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
	input wire pair_write;
	input wire [DATA_BITS - 1:0] alu_out;
	input wire [DATA_BITS - 1:0] lsu_out;
	input wire [DATA_BITS - 1:0] lsu_pair_out;
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
	localparam [2:0] MUX_CONST_HIGH = 3'b110;
	reg [DATA_BITS - 1:0] registers [12:0];
	wire [DATA_BITS - 1:0] reg_view [15:0];
	genvar _gv_gv_1;
	generate
		for (_gv_gv_1 = 0; _gv_gv_1 < 13; _gv_gv_1 = _gv_gv_1 + 1) begin : gen_regview
			localparam gv = _gv_gv_1;
			assign reg_view[gv] = registers[gv];
		end
	endgenerate
	assign reg_view[13] = {{DATA_BITS - 8 {1'b0}}, block_id};
	assign reg_view[14] = {{DATA_BITS - 8 {1'b0}}, THREADS_PER_BLOCK[7:0]};
	assign reg_view[15] = {{DATA_BITS - 8 {1'b0}}, THREAD_ID[7:0]};
	assign rs = reg_view[decoded_rs_address];
	assign rt = reg_view[decoded_rt_address];
	assign rd_data = reg_view[decoded_rd_address];
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
	wire pair_now = ((core_state == 3'b101) && pair_write) && (write_rd_address < 12);
	wire port_we = pair_now || ((core_state == 3'b110) && decoded_reg_write_enable);
	wire [3:0] port_addr = (pair_now ? write_rd_address + 4'd1 : write_rd_address);
	wire [DATA_BITS - 1:0] port_data = (pair_now ? lsu_pair_out : write_data);
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
			if (port_we && (port_addr < 13)) begin
				if (!pair_now && (decoded_reg_input_mux == MUX_CONST_HIGH))
					registers[port_addr][DATA_BITS - 1:8] <= decoded_immediate;
				else
					registers[port_addr] <= port_data;
			end
		end
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
module systolic_array (
	clk,
	reset,
	clear_acc,
	load_weights,
	load_broadcast,
	compute_enable,
	a_inputs_flat,
	b_inputs_flat,
	results_flat,
	ready
);
	parameter DATA_BITS = 16;
	parameter ARRAY_SIZE = 4;
	parameter PIPE_INTERVAL = ARRAY_SIZE;
	parameter NUMBER_FORMAT = 0;
	input wire clk;
	input wire reset;
	input wire clear_acc;
	input wire load_weights;
	input wire load_broadcast;
	input wire compute_enable;
	input wire signed [(DATA_BITS * ARRAY_SIZE) - 1:0] a_inputs_flat;
	input wire signed [(DATA_BITS * ARRAY_SIZE) - 1:0] b_inputs_flat;
	output wire [((DATA_BITS * ARRAY_SIZE) * ARRAY_SIZE) - 1:0] results_flat;
	output wire ready;
	reg signed [(DATA_BITS * ARRAY_SIZE) - 1:0] a_reg;
	reg signed [(DATA_BITS * ARRAY_SIZE) - 1:0] b_reg;
	function automatic [DATA_BITS - 1:0] canon;
		input [DATA_BITS - 1:0] x;
		canon = ((NUMBER_FORMAT == 0) && (x == {1'b1, {DATA_BITS - 1 {1'b0}}}) ? {DATA_BITS {1'b0}} : x);
	endfunction
	reg [ARRAY_SIZE - 1:0] ce_row;
	reg [ARRAY_SIZE - 1:0] ca_row;
	reg [ARRAY_SIZE - 1:0] lw_row;
	reg [ARRAY_SIZE - 1:0] bc_row;
	integer i;
	always @(posedge clk)
		if (reset) begin
			a_reg <= 1'sb0;
			b_reg <= 1'sb0;
			ce_row <= 1'sb0;
			ca_row <= 1'sb0;
			lw_row <= 1'sb0;
			bc_row <= 1'sb0;
		end
		else begin
			for (i = 0; i < ARRAY_SIZE; i = i + 1)
				begin
					a_reg[i * DATA_BITS+:DATA_BITS] <= canon(a_inputs_flat[i * DATA_BITS+:DATA_BITS]);
					b_reg[i * DATA_BITS+:DATA_BITS] <= canon(b_inputs_flat[i * DATA_BITS+:DATA_BITS]);
				end
			for (i = 0; i < ARRAY_SIZE; i = i + 1)
				begin
					ce_row[i] <= compute_enable;
					ca_row[i] <= clear_acc;
					lw_row[i] <= load_weights;
					bc_row[i] <= load_weights & load_broadcast;
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
				if (NUMBER_FORMAT == 0) begin : g_sf16
					systolic_pe pe(
						.clk(clk),
						.reset(reset),
						.clear_acc(ca_row[row]),
						.load_weight(lw_row[row]),
						.compute_enable(ce_row[row]),
						.a_in(a_wire[row][col]),
						.b_in((bc_row[row] ? b_wire[0][col] : b_wire[row][col])),
						.a_out(a_pe_out),
						.b_out(b_pe_out),
						.acc_raw(results[row][col])
					);
				end
				else begin : g_fp
					fp_systolic_pe #(
						.EXP_BITS((NUMBER_FORMAT == 2 ? 8 : 5)),
						.MANT_BITS((NUMBER_FORMAT == 2 ? 7 : 10)),
						.ALIGN_STAGE(1)
					) pe(
						.clk(clk),
						.reset(reset),
						.clear_acc(ca_row[row]),
						.load_weight(lw_row[row]),
						.compute_enable(ce_row[row]),
						.a_in(a_wire[row][col]),
						.b_in((bc_row[row] ? b_wire[0][col] : b_wire[row][col])),
						.a_out(a_pe_out),
						.b_out(b_pe_out),
						.acc(results[row][col])
					);
				end
				if (((col + 1) < ARRAY_SIZE) && (((col + 1) % PIPE_INTERVAL) == 0)) begin : g_a_pipe
					reg signed [DATA_BITS - 1:0] a_preg;
					always @(posedge clk)
						if (reset)
							a_preg <= 1'sb0;
						else
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
						else if (lw_row[row])
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
	clear_acc,
	load_weight,
	compute_enable,
	a_in,
	b_in,
	a_out,
	b_out,
	acc_raw
);
	parameter DATA_BITS = 16;
	input wire clk;
	input wire reset;
	input wire clear_acc;
	input wire load_weight;
	input wire compute_enable;
	input wire [DATA_BITS - 1:0] a_in;
	input wire [DATA_BITS - 1:0] b_in;
	output reg [DATA_BITS - 1:0] a_out;
	output reg [DATA_BITS - 1:0] b_out;
	output reg signed [15:0] acc_raw;
	reg valid_s0;
	reg valid_s1;
	reg [14:0] r3_mant;
	reg r3_sign;
	wire [29:0] prod = a_out[14:0] * b_out[14:0];
	wire [16:0] acc_ext = {acc_raw[15], acc_raw};
	wire [16:0] prd_op = {2'b00, r3_mant} ^ {17 {r3_sign}};
	wire [9:0] lo = ({1'b0, acc_ext[8:0]} + {1'b0, prd_op[8:0]}) + {9'b000000000, r3_sign};
	wire [7:0] hi0 = acc_ext[16:9] + prd_op[16:9];
	wire [7:0] hi1 = (acc_ext[16:9] + prd_op[16:9]) + 8'd1;
	wire c9 = lo[9];
	wire [16:0] sum = {(c9 ? hi1 : hi0), lo[8:0]};
	wire ovf = (c9 ? hi1[7] ^ hi1[6] : hi0[7] ^ hi0[6]);
	wire negz = (lo[8:0] == 9'd0) && (c9 ? hi1[6:0] == 7'h40 : hi0[6:0] == 7'h40);
	wire signed [15:0] sat = (ovf || negz ? (sum[16] ? 16'sh8001 : 16'sh7fff) : sum[15:0]);
	always @(posedge clk)
		if (reset) begin
			a_out <= {DATA_BITS {1'b0}};
			b_out <= {DATA_BITS {1'b0}};
			r3_mant <= 15'b000000000000000;
			r3_sign <= 1'b0;
			acc_raw <= 16'sb0000000000000000;
			valid_s0 <= 1'b0;
			valid_s1 <= 1'b0;
		end
		else begin
			a_out <= a_in;
			if (load_weight)
				b_out <= b_in;
			r3_mant <= prod[29:15];
			r3_sign <= a_out[15] ^ b_out[15];
			if (clear_acc) begin
				acc_raw <= 16'sb0000000000000000;
				valid_s0 <= 1'b0;
				valid_s1 <= 1'b0;
			end
			else begin
				valid_s0 <= compute_enable;
				valid_s1 <= valid_s0;
				if (valid_s1)
					acc_raw <= sat;
			end
		end
endmodule
`default_nettype none
module scratchpad (
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
	mem_write_ready,
	ram_en,
	ram_we,
	ram_addr,
	ram_di,
	ram_do
);
	parameter ADDR_BITS = 19;
	parameter DATA_BITS = 16;
	parameter NUM_PORTS = 4;
	parameter [ADDR_BITS - 1:0] BASE_ADDR = 19'h0ffc0;
	input wire clk;
	input wire reset;
	input wire [NUM_PORTS - 1:0] consumer_read_valid;
	input wire [(ADDR_BITS * NUM_PORTS) - 1:0] consumer_read_address_flat;
	output wire [NUM_PORTS - 1:0] consumer_read_ready;
	output wire [(DATA_BITS * NUM_PORTS) - 1:0] consumer_read_data_flat;
	input wire [NUM_PORTS - 1:0] consumer_write_valid;
	input wire [(ADDR_BITS * NUM_PORTS) - 1:0] consumer_write_address_flat;
	input wire [(DATA_BITS * NUM_PORTS) - 1:0] consumer_write_data_flat;
	output wire [NUM_PORTS - 1:0] consumer_write_ready;
	output wire [NUM_PORTS - 1:0] mem_read_valid;
	output wire [(ADDR_BITS * NUM_PORTS) - 1:0] mem_read_address_flat;
	input wire [NUM_PORTS - 1:0] mem_read_ready;
	input wire [(DATA_BITS * NUM_PORTS) - 1:0] mem_read_data_flat;
	output wire [NUM_PORTS - 1:0] mem_write_valid;
	output wire [(ADDR_BITS * NUM_PORTS) - 1:0] mem_write_address_flat;
	output wire [(DATA_BITS * NUM_PORTS) - 1:0] mem_write_data_flat;
	input wire [NUM_PORTS - 1:0] mem_write_ready;
	output wire ram_en;
	output wire [3:0] ram_we;
	output wire [4:0] ram_addr;
	output wire [31:0] ram_di;
	input wire [31:0] ram_do;
	localparam OFFSET_BITS = 6;
	localparam SEL_BITS = $clog2(NUM_PORTS);
	localparam ST_IDLE = 2'd0;
	localparam ST_READ_ISSUE = 2'd1;
	localparam ST_READ_DATA = 2'd2;
	localparam ST_WRITE = 2'd3;
	wire [ADDR_BITS - 1:0] c_raddr [NUM_PORTS - 1:0];
	wire [ADDR_BITS - 1:0] c_waddr [NUM_PORTS - 1:0];
	wire [DATA_BITS - 1:0] c_wdata [NUM_PORTS - 1:0];
	wire [DATA_BITS - 1:0] m_rdata [NUM_PORTS - 1:0];
	wire [NUM_PORTS - 1:0] read_in_window;
	wire [NUM_PORTS - 1:0] write_in_window;
	genvar _gv_gi_1;
	generate
		for (_gv_gi_1 = 0; _gv_gi_1 < NUM_PORTS; _gv_gi_1 = _gv_gi_1 + 1) begin : unpack
			localparam gi = _gv_gi_1;
			assign c_raddr[gi] = consumer_read_address_flat[gi * ADDR_BITS+:ADDR_BITS];
			assign c_waddr[gi] = consumer_write_address_flat[gi * ADDR_BITS+:ADDR_BITS];
			assign c_wdata[gi] = consumer_write_data_flat[gi * DATA_BITS+:DATA_BITS];
			assign m_rdata[gi] = mem_read_data_flat[gi * DATA_BITS+:DATA_BITS];
			assign read_in_window[gi] = c_raddr[gi] >= BASE_ADDR;
			assign write_in_window[gi] = c_waddr[gi] >= BASE_ADDR;
		end
	endgenerate
	reg [NUM_PORTS - 1:0] read_seen;
	reg [NUM_PORTS - 1:0] write_seen;
	reg [NUM_PORTS - 1:0] read_hit_q;
	reg [NUM_PORTS - 1:0] write_hit_q;
	always @(posedge clk)
		if (reset) begin
			read_seen <= {NUM_PORTS {1'b0}};
			write_seen <= {NUM_PORTS {1'b0}};
			read_hit_q <= {NUM_PORTS {1'b0}};
			write_hit_q <= {NUM_PORTS {1'b0}};
		end
		else begin
			read_seen <= consumer_read_valid;
			write_seen <= consumer_write_valid;
			read_hit_q <= consumer_read_valid & read_in_window;
			write_hit_q <= consumer_write_valid & write_in_window;
		end
	wire [NUM_PORTS - 1:0] read_live = consumer_read_valid & read_seen;
	wire [NUM_PORTS - 1:0] write_live = consumer_write_valid & write_seen;
	wire [NUM_PORTS - 1:0] read_hit = read_live & read_hit_q;
	wire [NUM_PORTS - 1:0] write_hit = write_live & write_hit_q;
	assign mem_read_valid = read_live & ~read_hit_q;
	assign mem_read_address_flat = consumer_read_address_flat;
	assign mem_write_valid = write_live & ~write_hit_q;
	assign mem_write_address_flat = consumer_write_address_flat;
	assign mem_write_data_flat = consumer_write_data_flat;
	reg [NUM_PORTS - 1:0] served;
	wire [NUM_PORTS - 1:0] write_pend = write_hit & ~served;
	wire [NUM_PORTS - 1:0] read_pend = read_hit & ~served;
	wire any_write_hit = |write_pend;
	wire any_read_hit = |read_pend;
	wire found = any_write_hit | any_read_hit;
	wire pick_write = any_write_hit;
	reg [SEL_BITS - 1:0] pick_w;
	reg [SEL_BITS - 1:0] pick_r;
	reg [5:0] pick_w_offset;
	reg [5:0] pick_r_offset;
	reg [DATA_BITS - 1:0] pick_wdata;
	integer pick_i;
	integer hit_i;
	always @(*) begin
		pick_w = {SEL_BITS {1'b0}};
		pick_r = {SEL_BITS {1'b0}};
		pick_w_offset = {OFFSET_BITS {1'b0}};
		pick_r_offset = {OFFSET_BITS {1'b0}};
		pick_wdata = {DATA_BITS {1'b0}};
		for (pick_i = NUM_PORTS - 1; pick_i >= 0; pick_i = pick_i - 1)
			begin
				if (write_pend[pick_i]) begin
					pick_w = pick_i[SEL_BITS - 1:0];
					pick_w_offset = c_waddr[pick_i][5:0];
					pick_wdata = c_wdata[pick_i];
				end
				if (read_pend[pick_i]) begin
					pick_r = pick_i[SEL_BITS - 1:0];
					pick_r_offset = c_raddr[pick_i][5:0];
				end
			end
	end
	wire [SEL_BITS - 1:0] pick = (pick_write ? pick_w : pick_r);
	wire [5:0] pick_offset = (pick_write ? pick_w_offset : pick_r_offset);
	reg [1:0] state;
	reg [SEL_BITS - 1:0] sel;
	reg [5:0] sel_offset;
	reg [DATA_BITS - 1:0] sel_wdata;
	reg [NUM_PORTS - 1:0] hit_read_ready;
	reg [NUM_PORTS - 1:0] hit_write_ready;
	reg [DATA_BITS - 1:0] hit_rdata [NUM_PORTS - 1:0];
	wire issuing = (state == ST_READ_ISSUE) || (state == ST_WRITE);
	assign ram_en = issuing || (state == ST_READ_DATA);
	assign ram_addr = sel_offset[5:1];
	assign ram_we = (state == ST_WRITE ? (sel_offset[0] ? 4'b1100 : 4'b0011) : 4'b0000);
	assign ram_di = (sel_offset[0] ? {sel_wdata, 16'h0000} : {16'h0000, sel_wdata});
	wire [DATA_BITS - 1:0] ram_half = (sel_offset[0] ? ram_do[31:16] : ram_do[15:0]);
	always @(posedge clk)
		if (reset) begin
			state <= ST_IDLE;
			sel <= {SEL_BITS {1'b0}};
			sel_offset <= {OFFSET_BITS {1'b0}};
			sel_wdata <= {DATA_BITS {1'b0}};
			hit_read_ready <= {NUM_PORTS {1'b0}};
			hit_write_ready <= {NUM_PORTS {1'b0}};
			served <= {NUM_PORTS {1'b0}};
			for (hit_i = 0; hit_i < NUM_PORTS; hit_i = hit_i + 1)
				hit_rdata[hit_i] <= {DATA_BITS {1'b0}};
		end
		else begin
			hit_read_ready <= {NUM_PORTS {1'b0}};
			hit_write_ready <= {NUM_PORTS {1'b0}};
			served <= served & (consumer_read_valid | consumer_write_valid);
			case (state)
				ST_IDLE:
					if (found) begin
						served[pick] <= 1'b1;
						sel <= pick;
						sel_offset <= pick_offset;
						sel_wdata <= pick_wdata;
						state <= (pick_write ? ST_WRITE : ST_READ_ISSUE);
					end
				ST_READ_ISSUE: state <= ST_READ_DATA;
				ST_READ_DATA: begin
					hit_rdata[sel] <= ram_half;
					hit_read_ready[sel] <= 1'b1;
					state <= ST_IDLE;
				end
				ST_WRITE: begin
					hit_write_ready[sel] <= 1'b1;
					state <= ST_IDLE;
				end
				default: state <= ST_IDLE;
			endcase
		end
	generate
		for (_gv_gi_1 = 0; _gv_gi_1 < NUM_PORTS; _gv_gi_1 = _gv_gi_1 + 1) begin : ready_mux
			localparam gi = _gv_gi_1;
			assign consumer_read_ready[gi] = (read_hit[gi] ? hit_read_ready[gi] : mem_read_ready[gi]);
			assign consumer_write_ready[gi] = (write_hit[gi] ? hit_write_ready[gi] : mem_write_ready[gi]);
			assign consumer_read_data_flat[gi * DATA_BITS+:DATA_BITS] = (read_hit[gi] ? hit_rdata[gi] : m_rdata[gi]);
		end
	endgenerate
endmodule
`default_nettype none
module tile_mem_queue (
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
	mem_read_address,
	mem_read_accept,
	mem_read_ready,
	mem_read_data,
	mem_write_valid,
	mem_write_address,
	mem_write_data,
	mem_write_accept
);
	parameter ADDR_BITS = 16;
	parameter DATA_BITS = 16;
	parameter NUM_CONSUMERS = 8;
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
	output reg mem_read_valid;
	output reg [ADDR_BITS - 1:0] mem_read_address;
	input wire mem_read_accept;
	input wire mem_read_ready;
	input wire [DATA_BITS - 1:0] mem_read_data;
	output reg mem_write_valid;
	output reg [ADDR_BITS - 1:0] mem_write_address;
	output reg [DATA_BITS - 1:0] mem_write_data;
	input wire mem_write_accept;
	localparam ID_BITS = (NUM_CONSUMERS > 1 ? $clog2(NUM_CONSUMERS) : 1);
	reg [NUM_CONSUMERS - 1:0] issued;
	wire [NUM_CONSUMERS - 1:0] pending = (consumer_read_valid | consumer_write_valid) & ~issued;
	reg slot_valid;
	reg slot_we;
	reg [ID_BITS - 1:0] slot_id;
	wire slot_taken = slot_valid & (slot_we ? mem_write_accept : mem_read_accept);
	reg [ID_BITS - 1:0] order [NUM_CONSUMERS - 1:0];
	reg [ID_BITS - 1:0] rd_ptr;
	reg [ID_BITS - 1:0] wr_ptr;
	reg [ID_BITS:0] count;
	wire push = slot_taken & ~slot_we;
	wire [ID_BITS - 1:0] head_id = (count == 0 ? slot_id : order[rd_ptr]);
	wire bypass = mem_read_ready & (count == 0);
	wire push_q = push & ~bypass;
	wire pop_q = mem_read_ready & (count != 0);
	reg [DATA_BITS - 1:0] rdata [NUM_CONSUMERS - 1:0];
	genvar _gv_gc_1;
	generate
		for (_gv_gc_1 = 0; _gv_gc_1 < NUM_CONSUMERS; _gv_gc_1 = _gv_gc_1 + 1) begin : data_out
			localparam gc = _gv_gc_1;
			assign consumer_read_data_flat[gc * DATA_BITS+:DATA_BITS] = rdata[gc];
		end
	endgenerate
	reg [ID_BITS - 1:0] rr;
	reg found;
	reg [ID_BITS - 1:0] pick;
	integer k;
	function automatic signed [ID_BITS - 1:0] sv2v_cast_7F6D4_signed;
		input reg signed [ID_BITS - 1:0] inp;
		sv2v_cast_7F6D4_signed = inp;
	endfunction
	always @(*) begin
		found = 1'b0;
		pick = {ID_BITS {1'b0}};
		for (k = (2 * NUM_CONSUMERS) - 1; k >= 0; k = k - 1)
			if (((k >= rr) && (k < (rr + NUM_CONSUMERS))) && pending[k % NUM_CONSUMERS]) begin
				found = 1'b1;
				pick = sv2v_cast_7F6D4_signed(k % NUM_CONSUMERS);
			end
	end
	integer i;
	always @(posedge clk)
		if (reset) begin
			issued <= {NUM_CONSUMERS {1'b0}};
			slot_valid <= 1'b0;
			slot_we <= 1'b0;
			slot_id <= {ID_BITS {1'b0}};
			mem_read_valid <= 1'b0;
			mem_write_valid <= 1'b0;
			mem_read_address <= {ADDR_BITS {1'b0}};
			mem_write_address <= {ADDR_BITS {1'b0}};
			mem_write_data <= {DATA_BITS {1'b0}};
			consumer_read_ready <= {NUM_CONSUMERS {1'b0}};
			consumer_write_ready <= {NUM_CONSUMERS {1'b0}};
			rd_ptr <= {ID_BITS {1'b0}};
			wr_ptr <= {ID_BITS {1'b0}};
			count <= {ID_BITS + 1 {1'b0}};
			rr <= {ID_BITS {1'b0}};
			for (i = 0; i < NUM_CONSUMERS; i = i + 1)
				rdata[i] <= {DATA_BITS {1'b0}};
		end
		else begin
			consumer_read_ready <= {NUM_CONSUMERS {1'b0}};
			consumer_write_ready <= {NUM_CONSUMERS {1'b0}};
			for (i = 0; i < NUM_CONSUMERS; i = i + 1)
				if ((!consumer_read_valid[i] && !consumer_write_valid[i]) && !(slot_valid && (slot_id == sv2v_cast_7F6D4_signed(i))))
					issued[i] <= 1'b0;
			if (slot_taken && slot_we)
				consumer_write_ready[slot_id] <= 1'b1;
			if (push_q) begin
				order[wr_ptr] <= slot_id;
				wr_ptr <= wr_ptr + 1'b1;
			end
			if (mem_read_ready) begin
				consumer_read_ready[head_id] <= 1'b1;
				rdata[head_id] <= mem_read_data;
			end
			if (pop_q)
				rd_ptr <= rd_ptr + 1'b1;
			count <= (count + {{ID_BITS {1'b0}}, push_q}) - {{ID_BITS {1'b0}}, pop_q};
			if (!slot_valid || slot_taken) begin
				slot_valid <= found;
				mem_read_valid <= found & ~consumer_write_valid[pick];
				mem_write_valid <= found & consumer_write_valid[pick];
				if (found) begin
					slot_id <= pick;
					slot_we <= consumer_write_valid[pick];
					issued[pick] <= 1'b1;
					rr <= (pick == sv2v_cast_7F6D4_signed(NUM_CONSUMERS - 1) ? {ID_BITS {1'b0}} : pick + 1'b1);
					mem_read_address <= consumer_read_address_flat[pick * ADDR_BITS+:ADDR_BITS];
					mem_write_address <= consumer_write_address_flat[pick * ADDR_BITS+:ADDR_BITS];
					mem_write_data <= consumer_write_data_flat[pick * DATA_BITS+:DATA_BITS];
				end
			end
		end
endmodule
`default_nettype wire
`default_nettype none

// Synthesizable 32×32 1RW scratchpad (128 B). Soft-flop implementation —
// Tiny Tapeout's hard RAM32 macro needs a post-PDN odb_power step that
// tt-gds-action / LibreLane cannot run.
module RAM32 (
    input             CLK,
    input      [3:0]  WE0,
    input             EN0,
    input      [4:0]  A0,
    input      [31:0] Di0,
    output reg [31:0] Do0
);
  reg [31:0] RAM[31:0];

  always @(posedge CLK)
    if (EN0) begin
      Do0 <= RAM[A0];
      if (WE0[0]) RAM[A0][7:0]   <= Di0[7:0];
      if (WE0[1]) RAM[A0][15:8]  <= Di0[15:8];
      if (WE0[2]) RAM[A0][23:16] <= Di0[23:16];
      if (WE0[3]) RAM[A0][31:24] <= Di0[31:24];
    end else begin
      Do0 <= 32'b0;
    end

endmodule
