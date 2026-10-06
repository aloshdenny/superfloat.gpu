`default_nettype none
module superfloat_openframe (
	clk,
	rst_n,
	start,
	done,
	core_active,
	bus_out,
	bus_sel,
	bus_we,
	bus_beat,
	bus_req,
	bus_in,
	bus_ack
);
	parameter NUM_CORES = 4;
	parameter THREADS_PER_BLOCK = 8;
	parameter SYSTOLIC_SIZE = 8;
	parameter PROGRAM_MEM_ADDR_BITS = 9;
	parameter DATA_MEM_ADDR_BITS = 19;
	parameter BUS_BITS = 16;
	parameter PROGRAM_CACHE_ENTRIES = 32;
	parameter NUMBER_FORMAT = 0;
	input wire clk;
	input wire rst_n;
	input wire start;
	output wire done;
	output wire [NUM_CORES - 1:0] core_active;
	output wire [BUS_BITS - 1:0] bus_out;
	output wire bus_sel;
	output wire bus_we;
	output wire bus_beat;
	output wire bus_req;
	input wire [BUS_BITS - 1:0] bus_in;
	input wire bus_ack;
	localparam NUM_PROG_CH = (PROGRAM_CACHE_ENTRIES > 0 ? 1 : NUM_CORES);
	localparam NUM_CH = NUM_PROG_CH + NUM_CORES;
	reg rst_s1;
	reg rst_s2;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			rst_s1 <= 1'b0;
			rst_s2 <= 1'b0;
		end
		else begin
			rst_s1 <= 1'b1;
			rst_s2 <= rst_s1;
		end
	wire chip_reset = !rst_s2;
	reg start_q1;
	reg start_q2;
	reg [7:0] thread_count_q;
	reg sync_mode_q;
	always @(posedge clk)
		if (chip_reset) begin
			start_q1 <= 1'b0;
			start_q2 <= 1'b0;
		end
		else begin
			start_q1 <= start;
			start_q2 <= start_q1;
		end
	localparam [2:0] L_IDLE = 3'd0;
	localparam [2:0] L_RESET = 3'd1;
	localparam [2:0] L_WAIT = 3'd2;
	localparam [2:0] L_DCR = 3'd3;
	localparam [2:0] L_RUN = 3'd4;
	reg [2:0] launch_state;
	reg [2:0] launch_count;
	always @(posedge clk)
		if (chip_reset) begin
			launch_state <= L_IDLE;
			launch_count <= 3'd0;
			thread_count_q <= 8'd0;
			sync_mode_q <= 1'b0;
		end
		else if (!start_q2)
			launch_state <= L_IDLE;
		else
			case (launch_state)
				L_IDLE: begin
					thread_count_q <= bus_in[7:0];
					sync_mode_q <= bus_in[8];
					launch_count <= 3'd0;
					launch_state <= L_RESET;
				end
				L_RESET: begin
					launch_count <= launch_count + 3'd1;
					if (launch_count == 3'd3) begin
						launch_count <= 3'd0;
						launch_state <= L_WAIT;
					end
				end
				L_WAIT: begin
					launch_count <= launch_count + 3'd1;
					if (launch_count == 3'd3)
						launch_state <= L_DCR;
				end
				L_DCR: launch_state <= L_RUN;
				default: launch_state <= L_RUN;
			endcase
	wire gpu_reset = (chip_reset || (launch_state == L_IDLE)) || (launch_state == L_RESET);
	wire gpu_start = launch_state == L_RUN;
	wire dcr_we = launch_state == L_DCR;
	wire gpu_done;
	assign done = gpu_done && gpu_start;
	wire [NUM_PROG_CH - 1:0] prog_valid;
	wire [(PROGRAM_MEM_ADDR_BITS * NUM_PROG_CH) - 1:0] prog_addr_flat;
	wire [NUM_PROG_CH - 1:0] prog_ready;
	wire [(16 * NUM_PROG_CH) - 1:0] prog_data_flat;
	wire [NUM_CORES - 1:0] dread_valid;
	wire [(DATA_MEM_ADDR_BITS * NUM_CORES) - 1:0] dread_addr_flat;
	wire [NUM_CORES - 1:0] dread_accept;
	wire [NUM_CORES - 1:0] dread_ready;
	wire [(16 * NUM_CORES) - 1:0] dread_data_flat;
	wire [NUM_CORES - 1:0] dwrite_valid;
	wire [(DATA_MEM_ADDR_BITS * NUM_CORES) - 1:0] dwrite_addr_flat;
	wire [(16 * NUM_CORES) - 1:0] dwrite_data_flat;
	wire [NUM_CORES - 1:0] dwrite_ready;
	gpu #(
		.DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
		.DATA_MEM_DATA_BITS(16),
		.DATA_MEM_NUM_CHANNELS(NUM_CORES),
		.PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
		.PROGRAM_MEM_DATA_BITS(16),
		.PROGRAM_MEM_NUM_CHANNELS(NUM_PROG_CH),
		.PROGRAM_CACHE_ENTRIES(PROGRAM_CACHE_ENTRIES),
		.NUM_CORES(NUM_CORES),
		.THREADS_PER_BLOCK(THREADS_PER_BLOCK),
		.SYSTOLIC_SIZE(SYSTOLIC_SIZE),
		.NUMBER_FORMAT(NUMBER_FORMAT)
	) gpu_inst(
		.clk(clk),
		.reset(gpu_reset),
		.start(gpu_start),
		.done(gpu_done),
		.device_control_write_enable(dcr_we),
		.device_control_data(thread_count_q),
		.program_mem_read_valid(prog_valid),
		.program_mem_read_address_flat(prog_addr_flat),
		.program_mem_read_ready(prog_ready),
		.program_mem_read_data_flat(prog_data_flat),
		.data_mem_read_valid(dread_valid),
		.data_mem_read_address_flat(dread_addr_flat),
		.data_mem_read_accept(dread_accept),
		.data_mem_read_ready(dread_ready),
		.data_mem_read_data_flat(dread_data_flat),
		.data_mem_write_valid(dwrite_valid),
		.data_mem_write_address_flat(dwrite_addr_flat),
		.data_mem_write_data_flat(dwrite_data_flat),
		.data_mem_write_ready(dwrite_ready),
		.core_active(core_active)
	);
	wire [NUM_CH - 1:0] ch_read_valid = {dread_valid, prog_valid};
	wire [NUM_CH - 1:0] ch_write_valid = {dwrite_valid, {NUM_PROG_CH {1'b0}}};
	wire [(BUS_BITS * NUM_CH) - 1:0] ch_read_addr_flat;
	wire [(BUS_BITS * NUM_CH) - 1:0] ch_write_addr_flat;
	wire [(BUS_BITS * NUM_CH) - 1:0] ch_write_data_flat;
	wire [NUM_CH - 1:0] ch_read_accept;
	wire [NUM_CH - 1:0] ch_read_ready;
	wire [NUM_CH - 1:0] ch_write_ready;
	wire [(BUS_BITS * NUM_CH) - 1:0] ch_read_data_flat;
	genvar _gv_c_1;
	function automatic [BUS_BITS - 1:0] sv2v_cast_25883;
		input reg [BUS_BITS - 1:0] inp;
		sv2v_cast_25883 = inp;
	endfunction
	generate
		for (_gv_c_1 = 0; _gv_c_1 < NUM_PROG_CH; _gv_c_1 = _gv_c_1 + 1) begin : program_channel_map
			localparam c = _gv_c_1;
			assign ch_read_addr_flat[c * BUS_BITS+:BUS_BITS] = sv2v_cast_25883(prog_addr_flat[c * PROGRAM_MEM_ADDR_BITS+:PROGRAM_MEM_ADDR_BITS]);
			assign ch_write_addr_flat[c * BUS_BITS+:BUS_BITS] = {BUS_BITS {1'b0}};
			assign ch_write_data_flat[c * BUS_BITS+:BUS_BITS] = {BUS_BITS {1'b0}};
			assign prog_ready[c] = ch_read_ready[c];
			assign prog_data_flat[c * 16+:16] = ch_read_data_flat[c * BUS_BITS+:16];
		end
		for (_gv_c_1 = 0; _gv_c_1 < NUM_CORES; _gv_c_1 = _gv_c_1 + 1) begin : data_channel_map
			localparam c = _gv_c_1;
			assign ch_read_addr_flat[(NUM_PROG_CH + c) * BUS_BITS+:BUS_BITS] = dread_addr_flat[c * DATA_MEM_ADDR_BITS+:BUS_BITS];
			assign ch_write_addr_flat[(NUM_PROG_CH + c) * BUS_BITS+:BUS_BITS] = dwrite_addr_flat[c * DATA_MEM_ADDR_BITS+:BUS_BITS];
			assign ch_write_data_flat[(NUM_PROG_CH + c) * BUS_BITS+:BUS_BITS] = dwrite_data_flat[c * 16+:16];
			assign dread_accept[c] = ch_read_accept[NUM_PROG_CH + c];
			assign dread_ready[c] = ch_read_ready[NUM_PROG_CH + c];
			assign dread_data_flat[c * 16+:16] = ch_read_data_flat[(NUM_PROG_CH + c) * BUS_BITS+:16];
			assign dwrite_ready[c] = ch_write_ready[NUM_PROG_CH + c];
		end
	endgenerate
	openframe_bus #(
		.NUM_CHANNELS(NUM_CH),
		.NUM_PROGRAM_CHANNELS(NUM_PROG_CH),
		.BUS_BITS(BUS_BITS)
	) bus(
		.clk(clk),
		.reset(chip_reset),
		.sync_mode(sync_mode_q),
		.flush(gpu_reset),
		.ch_read_valid(ch_read_valid),
		.ch_read_address_flat(ch_read_addr_flat),
		.ch_read_accept(ch_read_accept),
		.ch_read_ready(ch_read_ready),
		.ch_read_data_flat(ch_read_data_flat),
		.ch_write_valid(ch_write_valid),
		.ch_write_address_flat(ch_write_addr_flat),
		.ch_write_data_flat(ch_write_data_flat),
		.ch_write_ready(ch_write_ready),
		.bus_out(bus_out),
		.bus_sel(bus_sel),
		.bus_we(bus_we),
		.bus_beat(bus_beat),
		.bus_req(bus_req),
		.bus_in(bus_in),
		.bus_ack(bus_ack)
	);
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
	data_mem_read_accept,
	data_mem_read_ready,
	data_mem_read_data_flat,
	data_mem_write_valid,
	data_mem_write_address_flat,
	data_mem_write_data_flat,
	data_mem_write_ready,
	core_active
);
	parameter DATA_MEM_ADDR_BITS = 19;
	parameter DATA_MEM_DATA_BITS = 16;
	parameter DATA_MEM_NUM_CHANNELS = 4;
	parameter PROGRAM_MEM_ADDR_BITS = 9;
	parameter PROGRAM_MEM_DATA_BITS = 16;
	parameter PROGRAM_MEM_NUM_CHANNELS = 1;
	parameter PROGRAM_CACHE_ENTRIES = 32;
	parameter NUM_CORES = 4;
	parameter THREADS_PER_BLOCK = 8;
	parameter SYSTOLIC_SIZE = 8;
	parameter NUM_SYSTOLIC_ARRAYS = 1;
	parameter CACHE_SIZE = 2;
	parameter NUMBER_FORMAT = 0;
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
	input wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_read_accept;
	input wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_read_ready;
	input wire [(DATA_MEM_DATA_BITS * DATA_MEM_NUM_CHANNELS) - 1:0] data_mem_read_data_flat;
	output wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_write_valid;
	output wire [(DATA_MEM_ADDR_BITS * DATA_MEM_NUM_CHANNELS) - 1:0] data_mem_write_address_flat;
	output wire [(DATA_MEM_DATA_BITS * DATA_MEM_NUM_CHANNELS) - 1:0] data_mem_write_data_flat;
	input wire [DATA_MEM_NUM_CHANNELS - 1:0] data_mem_write_ready;
	output wire [NUM_CORES - 1:0] core_active;
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
	wire [NUM_CORES - 1:0] tile_prog_read_valid;
	wire [(PROGRAM_MEM_ADDR_BITS * NUM_CORES) - 1:0] tile_prog_read_address_flat;
	wire [NUM_CORES - 1:0] tile_prog_read_ready;
	wire [(PROGRAM_MEM_DATA_BITS * NUM_CORES) - 1:0] tile_prog_read_data_flat;
	wire [NUM_CORES - 1:0] tile_data_read_valid;
	wire [(DATA_MEM_ADDR_BITS * NUM_CORES) - 1:0] tile_data_read_address_flat;
	wire [NUM_CORES - 1:0] tile_data_read_accept;
	wire [NUM_CORES - 1:0] tile_data_read_ready;
	wire [(DATA_MEM_DATA_BITS * NUM_CORES) - 1:0] tile_data_read_data_flat;
	wire [NUM_CORES - 1:0] tile_data_write_valid;
	wire [(DATA_MEM_ADDR_BITS * NUM_CORES) - 1:0] tile_data_write_address_flat;
	wire [(DATA_MEM_DATA_BITS * NUM_CORES) - 1:0] tile_data_write_data_flat;
	wire [NUM_CORES - 1:0] tile_data_write_ready;
	wire [NUM_CORES - 1:0] prog_mem_write_ready_unused;
	wire [PROGRAM_MEM_NUM_CHANNELS - 1:0] prog_ext_write_valid_unused;
	wire [(PROGRAM_MEM_ADDR_BITS * PROGRAM_MEM_NUM_CHANNELS) - 1:0] prog_ext_write_address_flat_unused;
	wire [(PROGRAM_MEM_DATA_BITS * PROGRAM_MEM_NUM_CHANNELS) - 1:0] prog_ext_write_data_flat_unused;
	dcr dcr_instance(
		.clk(clk),
		.reset(reset_pipe2),
		.device_control_write_enable(device_control_write_enable),
		.device_control_data(device_control_data),
		.thread_count(thread_count)
	);
	generate
		if (DATA_MEM_NUM_CHANNELS == NUM_CORES) begin : data_direct
			assign data_mem_read_valid = tile_data_read_valid;
			assign data_mem_read_address_flat = tile_data_read_address_flat;
			assign tile_data_read_accept = data_mem_read_accept;
			assign tile_data_read_ready = data_mem_read_ready;
			assign tile_data_read_data_flat = data_mem_read_data_flat;
			assign data_mem_write_valid = tile_data_write_valid;
			assign data_mem_write_address_flat = tile_data_write_address_flat;
			assign data_mem_write_data_flat = tile_data_write_data_flat;
			assign tile_data_write_ready = data_mem_write_ready;
		end
		else begin : data_shared
			controller #(
				.ADDR_BITS(DATA_MEM_ADDR_BITS),
				.DATA_BITS(DATA_MEM_DATA_BITS),
				.NUM_CONSUMERS(NUM_CORES),
				.NUM_CHANNELS(DATA_MEM_NUM_CHANNELS)
			) data_mem_controller(
				.clk(clk),
				.reset(reset_pipe2),
				.consumer_read_valid(tile_data_read_valid),
				.consumer_read_address_flat(tile_data_read_address_flat),
				.consumer_read_ready(tile_data_read_ready),
				.consumer_read_data_flat(tile_data_read_data_flat),
				.consumer_write_valid(tile_data_write_valid),
				.consumer_write_address_flat(tile_data_write_address_flat),
				.consumer_write_data_flat(tile_data_write_data_flat),
				.consumer_write_ready(tile_data_write_ready),
				.mem_read_valid(data_mem_read_valid),
				.mem_read_address_flat(data_mem_read_address_flat),
				.mem_read_ready(data_mem_read_ready),
				.mem_read_data_flat(data_mem_read_data_flat),
				.mem_write_valid(data_mem_write_valid),
				.mem_write_address_flat(data_mem_write_address_flat),
				.mem_write_data_flat(data_mem_write_data_flat),
				.mem_write_ready(data_mem_write_ready)
			);
			assign tile_data_read_accept = tile_data_read_ready;
		end
		if (PROGRAM_CACHE_ENTRIES > 0) begin : program_cache
			shared_icache #(
				.NUM_PORTS(NUM_CORES),
				.ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
				.DATA_BITS(PROGRAM_MEM_DATA_BITS),
				.ENTRIES(PROGRAM_CACHE_ENTRIES)
			) icache(
				.clk(clk),
				.reset(reset_pipe2),
				.consumer_read_valid(tile_prog_read_valid),
				.consumer_read_address_flat(tile_prog_read_address_flat),
				.consumer_read_ready(tile_prog_read_ready),
				.consumer_read_data_flat(tile_prog_read_data_flat),
				.mem_read_valid(program_mem_read_valid[0]),
				.mem_read_address(program_mem_read_address_flat[PROGRAM_MEM_ADDR_BITS - 1:0]),
				.mem_read_ready(program_mem_read_ready[0]),
				.mem_read_data(program_mem_read_data_flat[PROGRAM_MEM_DATA_BITS - 1:0])
			);
		end
		else begin : program_controller
			controller #(
				.ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
				.DATA_BITS(PROGRAM_MEM_DATA_BITS),
				.NUM_CONSUMERS(NUM_CORES),
				.NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
				.WRITE_ENABLE(0)
			) program_mem_controller(
				.clk(clk),
				.reset(reset_pipe2),
				.consumer_read_valid(tile_prog_read_valid),
				.consumer_read_address_flat(tile_prog_read_address_flat),
				.consumer_read_ready(tile_prog_read_ready),
				.consumer_read_data_flat(tile_prog_read_data_flat),
				.consumer_write_valid({NUM_CORES {1'b0}}),
				.consumer_write_address_flat({PROGRAM_MEM_ADDR_BITS * NUM_CORES {1'b0}}),
				.consumer_write_data_flat({PROGRAM_MEM_DATA_BITS * NUM_CORES {1'b0}}),
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
		end
	endgenerate
	assign core_active = core_start & ~core_done;
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
	genvar _gv_i_1;
	generate
		for (_gv_i_1 = 0; _gv_i_1 < NUM_CORES; _gv_i_1 = _gv_i_1 + 1) begin : tiles
			localparam i = _gv_i_1;
			core_tile tile(
				.clk(clk),
				.reset(reset_pipe2),
				.core_reset(core_reset[i]),
				.start(core_start[i]),
				.done(core_done[i]),
				.block_id(core_block_id_flat[i * 8+:8]),
				.thread_count(core_thread_count_flat[i * TC_BITS+:TC_BITS]),
				.program_mem_read_valid(tile_prog_read_valid[i]),
				.program_mem_read_address(tile_prog_read_address_flat[i * PROGRAM_MEM_ADDR_BITS+:PROGRAM_MEM_ADDR_BITS]),
				.program_mem_read_ready(tile_prog_read_ready[i]),
				.program_mem_read_data(tile_prog_read_data_flat[i * PROGRAM_MEM_DATA_BITS+:PROGRAM_MEM_DATA_BITS]),
				.data_mem_read_valid(tile_data_read_valid[i]),
				.data_mem_read_address(tile_data_read_address_flat[i * DATA_MEM_ADDR_BITS+:DATA_MEM_ADDR_BITS]),
				.data_mem_read_accept(tile_data_read_accept[i]),
				.data_mem_read_ready(tile_data_read_ready[i]),
				.data_mem_read_data(tile_data_read_data_flat[i * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS]),
				.data_mem_write_valid(tile_data_write_valid[i]),
				.data_mem_write_address(tile_data_write_address_flat[i * DATA_MEM_ADDR_BITS+:DATA_MEM_ADDR_BITS]),
				.data_mem_write_data(tile_data_write_data_flat[i * DATA_MEM_DATA_BITS+:DATA_MEM_DATA_BITS]),
				.data_mem_write_ready(tile_data_write_ready[i])
			);
		end
	endgenerate
endmodule
`default_nettype none
module openframe_bus (
	clk,
	reset,
	sync_mode,
	flush,
	ch_read_valid,
	ch_read_address_flat,
	ch_read_accept,
	ch_read_ready,
	ch_read_data_flat,
	ch_write_valid,
	ch_write_address_flat,
	ch_write_data_flat,
	ch_write_ready,
	bus_out,
	bus_sel,
	bus_we,
	bus_beat,
	bus_req,
	bus_in,
	bus_ack
);
	parameter NUM_CHANNELS = 5;
	parameter NUM_PROGRAM_CHANNELS = 1;
	parameter BUS_BITS = 16;
	parameter OUTSTANDING = 8;
	parameter STICKY = 1;
	parameter SHARE_LINES = 8;
	input wire clk;
	input wire reset;
	input wire sync_mode;
	input wire flush;
	input wire [NUM_CHANNELS - 1:0] ch_read_valid;
	input wire [(BUS_BITS * NUM_CHANNELS) - 1:0] ch_read_address_flat;
	output wire [NUM_CHANNELS - 1:0] ch_read_accept;
	output reg [NUM_CHANNELS - 1:0] ch_read_ready;
	output wire [(BUS_BITS * NUM_CHANNELS) - 1:0] ch_read_data_flat;
	input wire [NUM_CHANNELS - 1:0] ch_write_valid;
	input wire [(BUS_BITS * NUM_CHANNELS) - 1:0] ch_write_address_flat;
	input wire [(BUS_BITS * NUM_CHANNELS) - 1:0] ch_write_data_flat;
	output wire [NUM_CHANNELS - 1:0] ch_write_ready;
	output reg [BUS_BITS - 1:0] bus_out;
	output reg bus_sel;
	output reg bus_we;
	output reg bus_beat;
	output reg bus_req;
	input wire [BUS_BITS - 1:0] bus_in;
	input wire bus_ack;
	localparam CH_BITS = (NUM_CHANNELS > 1 ? $clog2(NUM_CHANNELS) : 1);
	localparam Q_BITS = $clog2(OUTSTANDING);
	localparam [NUM_CHANNELS - 1:0] PROG_MASK = (1 << NUM_PROGRAM_CHANNELS) - 1;
	localparam [2:0] A_IDLE = 3'd0;
	localparam [2:0] A_ADDR = 3'd1;
	localparam [2:0] A_ADDR_WAIT = 3'd2;
	localparam [2:0] A_DATA = 3'd3;
	localparam [2:0] A_DATA_WAIT = 3'd4;
	reg [2:0] a_state;
	reg [CH_BITS - 1:0] cur;
	reg [CH_BITS - 1:0] rr;
	reg ack_q1;
	reg ack_q2;
	reg [BUS_BITS - 1:0] in_q;
	reg [BUS_BITS - 1:0] rdata;
	reg [NUM_CHANNELS - 1:0] shared_q;
	wire [BUS_BITS - 1:0] share_word;
	genvar _gv_gch_1;
	generate
		for (_gv_gch_1 = 0; _gv_gch_1 < NUM_CHANNELS; _gv_gch_1 = _gv_gch_1 + 1) begin : read_data_out
			localparam gch = _gv_gch_1;
			assign ch_read_data_flat[gch * BUS_BITS+:BUS_BITS] = (shared_q[gch] ? share_word : rdata);
		end
	endgenerate
	reg [NUM_CHANNELS - 1:0] a_accept;
	reg [NUM_CHANNELS - 1:0] a_wready;
	reg [NUM_CHANNELS - 1:0] room;
	assign ch_read_accept = (sync_mode ? room & ~PROG_MASK : a_accept);
	assign ch_write_ready = (sync_mode ? room & ~PROG_MASK : a_wready);
	reg [NUM_CHANNELS - 1:0] taken_q;
	reg [NUM_CHANNELS - 1:0] busy;
	reg [1:0] b_cnt [NUM_CHANNELS - 1:0];
	reg b0_we [NUM_CHANNELS - 1:0];
	reg b1_we [NUM_CHANNELS - 1:0];
	reg [BUS_BITS - 1:0] b0_addr [NUM_CHANNELS - 1:0];
	reg [BUS_BITS - 1:0] b1_addr [NUM_CHANNELS - 1:0];
	reg [BUS_BITS - 1:0] b0_data [NUM_CHANNELS - 1:0];
	reg [BUS_BITS - 1:0] b1_data [NUM_CHANNELS - 1:0];
	reg [NUM_CHANNELS - 1:0] q_mask [OUTSTANDING - 1:0];
	reg [Q_BITS - 1:0] q_rd;
	reg [Q_BITS - 1:0] q_wr;
	reg [Q_BITS:0] q_count;
	reg [BUS_BITS - 1:0] last_addr;
	reg last_sel;
	reg [BUS_BITS - 1:0] q_addr [OUTSTANDING - 1:0];
	reg q_sel [OUTSTANDING - 1:0];
	reg [OUTSTANDING - 1:0] q_stale;
	reg [Q_BITS:0] rcnt [NUM_CHANNELS - 1:0];
	reg w_beat;
	reg [BUS_BITS - 1:0] w_data;
	wire q_full = q_count == OUTSTANDING;
	wire answer = sync_mode & ack_q1;
	reg [NUM_CHANNELS - 1:0] r_valid;
	reg [NUM_CHANNELS - 1:0] r_we;
	reg [BUS_BITS - 1:0] r_addr [NUM_CHANNELS - 1:0];
	reg [BUS_BITS - 1:0] r_data [NUM_CHANNELS - 1:0];
	reg [BUS_BITS - 1:0] in_addr [NUM_CHANNELS - 1:0];
	integer c;
	always @(*)
		for (c = 0; c < NUM_CHANNELS; c = c + 1)
			begin
				in_addr[c] = (ch_write_valid[c] ? ch_write_address_flat[c * BUS_BITS+:BUS_BITS] : ch_read_address_flat[c * BUS_BITS+:BUS_BITS]);
				if (sync_mode && !PROG_MASK[c]) begin
					r_valid[c] = b_cnt[c] != 2'd0;
					r_we[c] = b0_we[c];
					r_addr[c] = b0_addr[c];
					r_data[c] = b0_data[c];
				end
				else begin
					r_valid[c] = ch_read_valid[c] | ch_write_valid[c];
					r_we[c] = ch_write_valid[c];
					r_addr[c] = in_addr[c];
					r_data[c] = ch_write_data_flat[c * BUS_BITS+:BUS_BITS];
				end
			end
	function automatic signed [NUM_CHANNELS - 1:0] sv2v_cast_7FC28_signed;
		input reg signed [NUM_CHANNELS - 1:0] inp;
		sv2v_cast_7FC28_signed = inp;
	endfunction
	wire [NUM_CHANNELS - 1:0] cur_mask = (a_state == A_IDLE ? {NUM_CHANNELS {1'b0}} : sv2v_cast_7FC28_signed(1) << cur);
	wire [NUM_CHANNELS - 1:0] share_hold;
	wire [NUM_CHANNELS - 1:0] eligible = ((((r_valid & ~taken_q) & ~busy) & ~cur_mask) & ~share_hold) & (r_we | {NUM_CHANNELS {~(sync_mode & q_full)}});
	reg found;
	reg [CH_BITS - 1:0] pick;
	integer k;
	function automatic signed [CH_BITS - 1:0] sv2v_cast_581D1_signed;
		input reg signed [CH_BITS - 1:0] inp;
		sv2v_cast_581D1_signed = inp;
	endfunction
	always @(*) begin
		found = 1'b0;
		pick = {CH_BITS {1'b0}};
		for (k = (2 * NUM_CHANNELS) - 1; k >= 0; k = k - 1)
			if (((k >= rr) && (k < (rr + NUM_CHANNELS))) && eligible[k % NUM_CHANNELS]) begin
				found = 1'b1;
				pick = sv2v_cast_581D1_signed(k % NUM_CHANNELS);
			end
	end
	reg [NUM_CHANNELS - 1:0] gnt;
	integer g;
	always @(*) begin
		gnt = {NUM_CHANNELS {1'b0}};
		for (g = (2 * NUM_CHANNELS) - 1; g >= 0; g = g - 1)
			if (((g >= rr) && (g < (rr + NUM_CHANNELS))) && eligible[g % NUM_CHANNELS])
				gnt = sv2v_cast_7FC28_signed(1) << (g % NUM_CHANNELS);
	end
	wire pick_we = |(gnt & r_we);
	wire pick_sel = pick >= NUM_PROGRAM_CHANNELS;
	wire [BUS_BITS - 1:0] pick_addr = r_addr[pick];
	wire [BUS_BITS - 1:0] pick_data = r_data[pick];
	wire acked = ack_q2 == bus_req;
	wire [Q_BITS - 1:0] q_newest = q_wr - 1'b1;
	reg [NUM_CHANNELS - 1:0] joins_ch;
	integer j;
	always @(*)
		for (j = 0; j < NUM_CHANNELS; j = j + 1)
			joins_ch[j] = ((last_sel == (j >= NUM_PROGRAM_CHANNELS)) && (last_addr == r_addr[j])) && !q_mask[q_newest][j];
	wire joins_newest = (((q_count != 0) && !(answer && (q_count == 1))) && !q_stale[q_newest]) && |(gnt & joins_ch);
	wire s_issue = (sync_mode & found) & ~w_beat;
	wire w_issue = s_issue & pick_we;
	wire [CH_BITS - 1:0] next_rr = (pick == sv2v_cast_581D1_signed(NUM_CHANNELS - 1) ? {CH_BITS {1'b0}} : pick + 1'b1);
	wire [NUM_CHANNELS - 1:0] share_take;
	reg [NUM_CHANNELS - 1:0] b_push;
	reg [NUM_CHANNELS - 1:0] b_pop;
	reg [1:0] b_next [NUM_CHANNELS - 1:0];
	always @(*)
		for (c = 0; c < NUM_CHANNELS; c = c + 1)
			begin
				b_push[c] = ((sync_mode && !PROG_MASK[c]) && room[c]) && (ch_read_valid[c] || ch_write_valid[c]);
				b_pop[c] = ((s_issue && (pick == sv2v_cast_581D1_signed(c))) && !PROG_MASK[c]) || share_take[c];
				b_next[c] = (b_cnt[c] + {1'b0, b_push[c]}) - {1'b0, b_pop[c]};
			end
	function automatic [Q_BITS - 1:0] sv2v_cast_B2E04;
		input reg [Q_BITS - 1:0] inp;
		sv2v_cast_B2E04 = inp;
	endfunction
	function automatic signed [SHARE_LINES - 1:0] sv2v_cast_196BC_signed;
		input reg signed [SHARE_LINES - 1:0] inp;
		sv2v_cast_196BC_signed = inp;
	endfunction
	generate
		if (SHARE_LINES > 0) begin : g_share
			localparam LB = (SHARE_LINES > 1 ? $clog2(SHARE_LINES) : 1);
			reg [BUS_BITS - 4:0] s_tag [SHARE_LINES - 1:0];
			reg [SHARE_LINES - 1:0] s_lvalid;
			reg [7:0] s_wvalid [SHARE_LINES - 1:0];
			reg [BUS_BITS - 1:0] s_data [(8 * SHARE_LINES) - 1:0];
			reg wr_en;
			reg [SHARE_LINES - 1:0] wr_lines;
			reg [2:0] wr_word;
			reg [BUS_BITS - 1:0] wr_data;
			reg [LB - 1:0] s_next;
			reg [CH_BITS - 1:0] s_rr;
			reg [SHARE_LINES - 1:0] e0_hit [NUM_CHANNELS - 1:0];
			reg [SHARE_LINES - 1:0] e1_hit [NUM_CHANNELS - 1:0];
			reg [SHARE_LINES - 1:0] s_match [NUM_CHANNELS - 1:0];
			reg [NUM_CHANNELS - 1:0] hold;
			reg [NUM_CHANNELS - 1:0] hit;
			reg [NUM_CHANNELS - 1:0] hold_q;
			integer sc;
			always @(*)
				for (sc = 0; sc < NUM_CHANNELS; sc = sc + 1)
					begin
						s_match[sc] = e0_hit[sc];
						hold[sc] = sync_mode && hold_q[sc];
						hit[sc] = hold[sc] && (rcnt[sc] == {(Q_BITS >= 0 ? Q_BITS + 1 : 1 - Q_BITS) {1'sb0}});
					end
			assign share_hold = hold;
			reg s_found;
			reg [CH_BITS - 1:0] s_pick;
			integer sk;
			integer sw;
			always @(*) begin
				s_found = 1'b0;
				s_pick = {CH_BITS {1'b0}};
				for (sk = (2 * NUM_CHANNELS) - 1; sk >= 0; sk = sk - 1)
					if (((sk >= s_rr) && (sk < (s_rr + NUM_CHANNELS))) && hit[sk % NUM_CHANNELS]) begin
						s_found = 1'b1;
						s_pick = sv2v_cast_581D1_signed(sk % NUM_CHANNELS);
					end
			end
			assign share_take = (s_found ? sv2v_cast_7FC28_signed(1) << s_pick : {NUM_CHANNELS {1'b0}});
			reg [SHARE_LINES - 1:0] sh_lines;
			reg [2:0] sh_word;
			reg [BUS_BITS - 1:0] sh_data;
			always @(posedge clk) begin
				sh_lines <= s_match[s_pick];
				sh_word <= b0_addr[s_pick][2:0];
			end
			always @(*) begin
				sh_data = {BUS_BITS {1'b0}};
				for (sw = 0; sw < SHARE_LINES; sw = sw + 1)
					if (sh_lines[sw])
						sh_data = s_data[(8 * sw) + sh_word];
			end
			assign share_word = sh_data;
			wire fill = (answer && q_sel[q_rd]) && !q_stale[q_rd];
			wire [Q_BITS - 1:0] q_rd_next = q_rd + sv2v_cast_B2E04(answer);
			reg [BUS_BITS - 1:0] f_addr;
			always @(posedge clk) f_addr <= q_addr[q_rd_next];
			reg [SHARE_LINES - 1:0] f_match;
			integer sf;
			integer su;
			integer sv;
			always @(*)
				for (sf = 0; sf < SHARE_LINES; sf = sf + 1)
					f_match[sf] = s_lvalid[sf] && (s_tag[sf] == f_addr[BUS_BITS - 1:3]);
			wire s_clear = (flush || w_issue) || !sync_mode;
			wire s_repl = fill && !(|f_match);
			wire [SHARE_LINES - 1:0] s_repl_mask = (s_repl ? sv2v_cast_196BC_signed(1) << s_next : {SHARE_LINES {1'b0}});
			wire [SHARE_LINES - 1:0] s_fill_mask = (!fill ? {SHARE_LINES {1'b0}} : (|f_match ? f_match : s_repl_mask));
			reg [SHARE_LINES - 1:0] in_look [NUM_CHANNELS - 1:0];
			reg [SHARE_LINES - 1:0] in_next [NUM_CHANNELS - 1:0];
			reg [SHARE_LINES - 1:0] e0_next [NUM_CHANNELS - 1:0];
			reg [SHARE_LINES - 1:0] e1_next [NUM_CHANNELS - 1:0];
			integer sn;
			integer sm;
			always @(*)
				for (sn = 0; sn < NUM_CHANNELS; sn = sn + 1)
					begin
						for (sm = 0; sm < SHARE_LINES; sm = sm + 1)
							in_look[sn][sm] = (s_lvalid[sm] && (s_tag[sm] == in_addr[sn][BUS_BITS - 1:3])) && s_wvalid[sm][in_addr[sn][2:0]];
						in_next[sn] = (s_clear ? {SHARE_LINES {1'b0}} : (in_look[sn] & ~s_repl_mask) | (in_addr[sn] == f_addr ? s_fill_mask : {SHARE_LINES {1'b0}}));
						e0_next[sn] = (s_clear ? {SHARE_LINES {1'b0}} : (e0_hit[sn] & ~s_repl_mask) | (b0_addr[sn] == f_addr ? s_fill_mask : {SHARE_LINES {1'b0}}));
						e1_next[sn] = (s_clear ? {SHARE_LINES {1'b0}} : (e1_hit[sn] & ~s_repl_mask) | (b1_addr[sn] == f_addr ? s_fill_mask : {SHARE_LINES {1'b0}}));
					end
			reg [SHARE_LINES - 1:0] e0_nx [NUM_CHANNELS - 1:0];
			reg [SHARE_LINES - 1:0] e1_nx [NUM_CHANNELS - 1:0];
			reg [NUM_CHANNELS - 1:0] to_e0;
			reg [NUM_CHANNELS - 1:0] b0_we_nx;
			integer sp;
			always @(*)
				for (sp = 0; sp < NUM_CHANNELS; sp = sp + 1)
					begin
						to_e0[sp] = b_push[sp] && ((b_cnt[sp] - {1'b0, b_pop[sp]}) == 2'd0);
						e0_nx[sp] = (to_e0[sp] ? in_next[sp] : (b_pop[sp] ? e1_next[sp] : e0_next[sp]));
						e1_nx[sp] = (b_push[sp] && !to_e0[sp] ? in_next[sp] : e1_next[sp]);
						b0_we_nx[sp] = (to_e0[sp] ? ch_write_valid[sp] : (b_pop[sp] ? b1_we[sp] : b0_we[sp]));
					end
			reg [NUM_CHANNELS - 1:0] hold_nx;
			reg h_e0;
			reg h_e1;
			reg h_in;
			integer sh;
			always @(*)
				for (sh = 0; sh < NUM_CHANNELS; sh = sh + 1)
					begin
						h_e0 = !b0_we[sh] && |e0_next[sh];
						h_e1 = !b1_we[sh] && |e1_next[sh];
						h_in = !ch_write_valid[sh] && |in_next[sh];
						case ({b_push[sh], b_pop[sh]})
							2'b00: hold_nx[sh] = (b_cnt[sh] != 2'd0) && h_e0;
							2'b01: hold_nx[sh] = (b_cnt[sh] != 2'd1) && h_e1;
							2'b10: hold_nx[sh] = (b_cnt[sh] == 2'd0 ? h_in : (b_cnt[sh] != 2'd3) && h_e0);
							default: hold_nx[sh] = (b_cnt[sh] != 2'd0) && (b_cnt[sh] == 2'd1 ? h_in : h_e1);
						endcase
					end
			integer se;
			always @(posedge clk)
				for (se = 0; se < NUM_CHANNELS; se = se + 1)
					if (reset || PROG_MASK[se]) begin
						e0_hit[se] <= {SHARE_LINES {1'b0}};
						e1_hit[se] <= {SHARE_LINES {1'b0}};
						hold_q[se] <= 1'b0;
					end
					else begin
						e0_hit[se] <= e0_nx[se];
						e1_hit[se] <= e1_nx[se];
						hold_q[se] <= hold_nx[se];
					end
			always @(posedge clk)
				if (reset) begin
					s_lvalid <= {SHARE_LINES {1'b0}};
					s_next <= {LB {1'b0}};
					s_rr <= {CH_BITS {1'b0}};
				end
				else begin
					if (s_found)
						s_rr <= (s_pick == sv2v_cast_581D1_signed(NUM_CHANNELS - 1) ? {CH_BITS {1'b0}} : s_pick + 1'b1);
					if (s_repl) begin
						s_lvalid[s_next] <= 1'b1;
						begin : sv2v_autoblock_1
							reg signed [LB - 1:0] sv2v_tmp_cast;
							sv2v_tmp_cast = SHARE_LINES - 1;
							s_next <= (s_next == sv2v_tmp_cast ? {LB {1'b0}} : s_next + 1'b1);
						end
					end
					if ((flush || w_issue) || !sync_mode)
						s_lvalid <= {SHARE_LINES {1'b0}};
				end
			always @(posedge clk)
				if (fill) begin
					if (|f_match) begin
						for (su = 0; su < SHARE_LINES; su = su + 1)
							if (f_match[su])
								s_wvalid[su][f_addr[2:0]] <= 1'b1;
					end
					else begin
						s_tag[s_next] <= f_addr[BUS_BITS - 1:3];
						s_wvalid[s_next] <= 8'b00000001 << f_addr[2:0];
					end
				end
			always @(posedge clk) begin
				wr_en <= fill;
				wr_lines <= (|f_match ? f_match : sv2v_cast_196BC_signed(1) << s_next);
				wr_word <= f_addr[2:0];
				wr_data <= in_q;
				if (wr_en) begin
					for (sv = 0; sv < SHARE_LINES; sv = sv + 1)
						if (wr_lines[sv])
							s_data[(8 * sv) + wr_word] <= wr_data;
				end
			end
		end
		else begin : g_no_share
			assign share_hold = {NUM_CHANNELS {1'b0}};
			assign share_take = {NUM_CHANNELS {1'b0}};
			assign share_word = {BUS_BITS {1'b0}};
		end
	endgenerate
	integer i;
	always @(posedge clk)
		if (reset) begin
			a_state <= A_IDLE;
			cur <= {CH_BITS {1'b0}};
			rr <= {CH_BITS {1'b0}};
			ack_q1 <= 1'b0;
			ack_q2 <= 1'b0;
			in_q <= {BUS_BITS {1'b0}};
			rdata <= {BUS_BITS {1'b0}};
			a_accept <= {NUM_CHANNELS {1'b0}};
			a_wready <= {NUM_CHANNELS {1'b0}};
			room <= ~PROG_MASK;
			taken_q <= {NUM_CHANNELS {1'b0}};
			busy <= {NUM_CHANNELS {1'b0}};
			q_rd <= {Q_BITS {1'b0}};
			q_wr <= {Q_BITS {1'b0}};
			q_count <= {Q_BITS + 1 {1'b0}};
			last_addr <= {BUS_BITS {1'b0}};
			last_sel <= 1'b0;
			q_stale <= {OUTSTANDING {1'b0}};
			shared_q <= {NUM_CHANNELS {1'b0}};
			for (i = 0; i < NUM_CHANNELS; i = i + 1)
				rcnt[i] <= 1'sb0;
			w_beat <= 1'b0;
			w_data <= {BUS_BITS {1'b0}};
			ch_read_ready <= {NUM_CHANNELS {1'b0}};
			bus_out <= {BUS_BITS {1'b0}};
			bus_sel <= 1'b0;
			bus_we <= 1'b0;
			bus_beat <= 1'b0;
			bus_req <= 1'b0;
			for (i = 0; i < NUM_CHANNELS; i = i + 1)
				b_cnt[i] <= 2'd0;
		end
		else begin
			ack_q1 <= bus_ack;
			ack_q2 <= ack_q1;
			in_q <= bus_in;
			a_accept <= {NUM_CHANNELS {1'b0}};
			a_wready <= {NUM_CHANNELS {1'b0}};
			ch_read_ready <= {NUM_CHANNELS {1'b0}};
			taken_q <= {NUM_CHANNELS {1'b0}};
			if (!sync_mode) begin
				shared_q <= {NUM_CHANNELS {1'b0}};
				case (a_state)
					A_IDLE:
						if (found) begin
							cur <= pick;
							rr <= next_rr;
							bus_sel <= pick_sel;
							bus_we <= pick_we;
							bus_beat <= 1'b0;
							bus_out <= pick_addr;
							a_state <= A_ADDR;
						end
					A_ADDR: begin
						bus_req <= ~bus_req;
						a_state <= A_ADDR_WAIT;
					end
					A_DATA: begin
						bus_req <= ~bus_req;
						a_state <= A_DATA_WAIT;
					end
					A_ADDR_WAIT, A_DATA_WAIT:
						if ((acked && (a_state == A_ADDR_WAIT)) && bus_we) begin
							bus_out <= r_data[cur];
							bus_beat <= 1'b1;
							a_state <= A_DATA;
						end
						else if (acked) begin
							if (bus_we)
								a_wready[cur] <= 1'b1;
							else begin
								rdata <= bus_in;
								ch_read_ready[cur] <= 1'b1;
								a_accept[cur] <= 1'b1;
							end
							taken_q[cur] <= 1'b1;
							if (found) begin
								cur <= pick;
								rr <= next_rr;
								bus_sel <= pick_sel;
								bus_we <= pick_we;
								bus_beat <= 1'b0;
								bus_out <= pick_addr;
								a_state <= A_ADDR;
							end
							else
								a_state <= A_IDLE;
						end
					default: a_state <= A_IDLE;
				endcase
			end
			else begin
				bus_req <= 1'b0;
				ch_read_ready <= (answer ? q_mask[q_rd] : {NUM_CHANNELS {1'b0}}) | share_take;
				shared_q <= share_take;
				if (answer) begin
					rdata <= in_q;
					busy <= busy & ~q_mask[q_rd];
					taken_q <= q_mask[q_rd] & PROG_MASK;
					q_rd <= q_rd + 1'b1;
				end
				if (w_beat) begin
					bus_out <= w_data;
					bus_we <= 1'b1;
					bus_beat <= 1'b1;
					bus_req <= 1'b1;
					w_beat <= 1'b0;
				end
				else if (found) begin
					rr <= (STICKY ? pick : next_rr);
					if (pick_we) begin
						q_stale <= {OUTSTANDING {1'b1}};
						bus_out <= pick_addr;
						bus_sel <= 1'b1;
						bus_we <= 1'b1;
						bus_beat <= 1'b0;
						bus_req <= 1'b1;
						w_beat <= 1'b1;
						w_data <= pick_data;
					end
					else begin
						if (joins_newest)
							q_mask[q_newest][pick] <= 1'b1;
						else begin
							bus_out <= pick_addr;
							bus_sel <= pick_sel;
							bus_we <= 1'b0;
							bus_beat <= 1'b0;
							bus_req <= 1'b1;
							q_mask[q_wr] <= sv2v_cast_7FC28_signed(1) << pick;
							q_addr[q_wr] <= pick_addr;
							q_sel[q_wr] <= pick_sel;
							q_stale[q_wr] <= 1'b0;
							q_wr <= q_wr + 1'b1;
							last_addr <= pick_addr;
							last_sel <= pick_sel;
						end
						if (PROG_MASK[pick]) begin
							busy[pick] <= 1'b1;
							taken_q[pick] <= 1'b1;
						end
					end
				end
				q_count <= (q_count + {{Q_BITS {1'b0}}, (s_issue && !pick_we) && !joins_newest}) - {{Q_BITS {1'b0}}, answer};
				for (i = 0; i < NUM_CHANNELS; i = i + 1)
					rcnt[i] <= (rcnt[i] + {{Q_BITS {1'b0}}, (s_issue && !pick_we) && (pick == sv2v_cast_581D1_signed(i))}) - {{Q_BITS {1'b0}}, answer && q_mask[q_rd][i]};
				for (i = 0; i < NUM_CHANNELS; i = i + 1)
					if (!PROG_MASK[i]) begin
						if (b_pop[i]) begin
							b0_we[i] <= b1_we[i];
							b0_addr[i] <= b1_addr[i];
							b0_data[i] <= b1_data[i];
						end
						if (b_push[i]) begin
							if ((b_cnt[i] - {1'b0, b_pop[i]}) == 2'd0) begin
								b0_we[i] <= ch_write_valid[i];
								b0_addr[i] <= in_addr[i];
								b0_data[i] <= ch_write_data_flat[i * BUS_BITS+:BUS_BITS];
							end
							else begin
								b1_we[i] <= ch_write_valid[i];
								b1_addr[i] <= in_addr[i];
								b1_data[i] <= ch_write_data_flat[i * BUS_BITS+:BUS_BITS];
							end
						end
						b_cnt[i] <= b_next[i];
						room[i] <= b_next[i] <= 2'd1;
					end
					else begin
						b0_we[i] <= 1'b0;
						b1_we[i] <= 1'b0;
						b0_addr[i] <= {BUS_BITS {1'b0}};
						b1_addr[i] <= {BUS_BITS {1'b0}};
						b0_data[i] <= {BUS_BITS {1'b0}};
						b1_data[i] <= {BUS_BITS {1'b0}};
					end
			end
		end
endmodule
`default_nettype wire
`default_nettype none
module shared_icache (
	clk,
	reset,
	consumer_read_valid,
	consumer_read_address_flat,
	consumer_read_ready,
	consumer_read_data_flat,
	mem_read_valid,
	mem_read_address,
	mem_read_ready,
	mem_read_data
);
	parameter NUM_PORTS = 4;
	parameter ADDR_BITS = 9;
	parameter DATA_BITS = 16;
	parameter ENTRIES = 32;
	input wire clk;
	input wire reset;
	input wire [NUM_PORTS - 1:0] consumer_read_valid;
	input wire [(ADDR_BITS * NUM_PORTS) - 1:0] consumer_read_address_flat;
	output reg [NUM_PORTS - 1:0] consumer_read_ready;
	output wire [(DATA_BITS * NUM_PORTS) - 1:0] consumer_read_data_flat;
	output reg mem_read_valid;
	output reg [ADDR_BITS - 1:0] mem_read_address;
	input wire mem_read_ready;
	input wire [DATA_BITS - 1:0] mem_read_data;
	localparam INDEX_BITS = $clog2(ENTRIES);
	localparam TAG_BITS = (ADDR_BITS > INDEX_BITS ? ADDR_BITS - INDEX_BITS : 1);
	localparam PORT_BITS = (NUM_PORTS > 1 ? $clog2(NUM_PORTS) : 1);
	localparam [1:0] S_PICK = 2'd0;
	localparam [1:0] S_LOOKUP = 2'd1;
	localparam [1:0] S_FILL = 2'd2;
	localparam [1:0] S_DONE = 2'd3;
	reg [DATA_BITS - 1:0] data_mem [ENTRIES - 1:0];
	reg [TAG_BITS - 1:0] tag_mem [ENTRIES - 1:0];
	reg [ENTRIES - 1:0] line_valid;
	reg [1:0] state;
	reg [ADDR_BITS - 1:0] cur_addr;
	reg [PORT_BITS - 1:0] rr_next;
	reg [DATA_BITS - 1:0] out_data;
	wire [ADDR_BITS - 1:0] port_addr [NUM_PORTS - 1:0];
	genvar _gv_gp_1;
	generate
		for (_gv_gp_1 = 0; _gv_gp_1 < NUM_PORTS; _gv_gp_1 = _gv_gp_1 + 1) begin : ports
			localparam gp = _gv_gp_1;
			assign port_addr[gp] = consumer_read_address_flat[gp * ADDR_BITS+:ADDR_BITS];
			assign consumer_read_data_flat[gp * DATA_BITS+:DATA_BITS] = out_data;
		end
	endgenerate
	reg found;
	reg [PORT_BITS - 1:0] pick;
	integer k;
	function automatic signed [PORT_BITS - 1:0] sv2v_cast_EF1C1_signed;
		input reg signed [PORT_BITS - 1:0] inp;
		sv2v_cast_EF1C1_signed = inp;
	endfunction
	always @(*) begin
		found = 1'b0;
		pick = {PORT_BITS {1'b0}};
		for (k = (2 * NUM_PORTS) - 1; k >= 0; k = k - 1)
			if (((k >= rr_next) && (k < (rr_next + NUM_PORTS))) && consumer_read_valid[k % NUM_PORTS]) begin
				found = 1'b1;
				pick = sv2v_cast_EF1C1_signed(k % NUM_PORTS);
			end
	end
	wire [INDEX_BITS - 1:0] cur_index = cur_addr[INDEX_BITS - 1:0];
	function automatic [TAG_BITS - 1:0] sv2v_cast_A3C7D;
		input reg [TAG_BITS - 1:0] inp;
		sv2v_cast_A3C7D = inp;
	endfunction
	wire [TAG_BITS - 1:0] cur_tag = (ADDR_BITS > INDEX_BITS ? sv2v_cast_A3C7D(cur_addr >> INDEX_BITS) : {TAG_BITS {1'b0}});
	wire hit = line_valid[cur_index] && (tag_mem[cur_index] == cur_tag);
	reg [NUM_PORTS - 1:0] waiting_on_cur;
	integer w;
	always @(*)
		for (w = 0; w < NUM_PORTS; w = w + 1)
			waiting_on_cur[w] = consumer_read_valid[w] && (port_addr[w] == cur_addr);
	always @(posedge clk)
		if (reset) begin
			state <= S_PICK;
			cur_addr <= {ADDR_BITS {1'b0}};
			rr_next <= {PORT_BITS {1'b0}};
			out_data <= {DATA_BITS {1'b0}};
			line_valid <= {ENTRIES {1'b0}};
			consumer_read_ready <= {NUM_PORTS {1'b0}};
			mem_read_valid <= 1'b0;
			mem_read_address <= {ADDR_BITS {1'b0}};
		end
		else begin
			consumer_read_ready <= {NUM_PORTS {1'b0}};
			case (state)
				S_PICK:
					if (found) begin
						cur_addr <= port_addr[pick];
						rr_next <= (pick == sv2v_cast_EF1C1_signed(NUM_PORTS - 1) ? {PORT_BITS {1'b0}} : pick + 1'b1);
						state <= S_LOOKUP;
					end
				S_LOOKUP:
					if (hit) begin
						out_data <= data_mem[cur_index];
						consumer_read_ready <= waiting_on_cur;
						state <= S_DONE;
					end
					else begin
						mem_read_valid <= 1'b1;
						mem_read_address <= cur_addr;
						state <= S_FILL;
					end
				S_FILL:
					if (mem_read_ready) begin
						mem_read_valid <= 1'b0;
						data_mem[cur_index] <= mem_read_data;
						tag_mem[cur_index] <= cur_tag;
						line_valid[cur_index] <= 1'b1;
						out_data <= mem_read_data;
						consumer_read_ready <= waiting_on_cur;
						state <= S_DONE;
					end
				S_DONE: state <= S_PICK;
				default: state <= S_PICK;
			endcase
		end
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
	reg [7:0] total_blocks;
	reg [7:0] last_block;
	reg [TC_BITS - 1:0] last_block_threads;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	function automatic [TC_BITS - 1:0] sv2v_cast_9FF7A;
		input reg [TC_BITS - 1:0] inp;
		sv2v_cast_9FF7A = inp;
	endfunction
	always @(posedge clk) begin
		total_blocks <= sv2v_cast_8(((sv2v_cast_32(thread_count) + THREADS_PER_BLOCK) - 1) / THREADS_PER_BLOCK);
		last_block <= sv2v_cast_8(((sv2v_cast_32(thread_count) + THREADS_PER_BLOCK) - 1) / THREADS_PER_BLOCK) - 8'd1;
		last_block_threads <= sv2v_cast_9FF7A(sv2v_cast_32(thread_count) - (((sv2v_cast_32(thread_count) - 1) / THREADS_PER_BLOCK) * THREADS_PER_BLOCK));
	end
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
			if (start_execution && (blocks_done == total_blocks))
				done <= 1;
			begin : dispatch_block
				reg [7:0] block_idx;
				reg [7:0] waiting_before;
				reg [7:0] remaining;
				waiting_before = 8'd0;
				remaining = total_blocks - blocks_dispatched;
				for (i = 0; i < NUM_CORES; i = i + 1)
					if (start_execution && core_reset[i]) begin
						core_reset[i] <= 0;
						block_idx = blocks_dispatched + waiting_before;
						if (waiting_before < remaining) begin
							core_start[i] <= 1;
							core_block_id[i] <= block_idx;
							core_thread_count[i] <= (block_idx == last_block ? last_block_threads : sv2v_cast_9FF7A_signed(THREADS_PER_BLOCK));
						end
						waiting_before = waiting_before + 8'd1;
					end
				blocks_dispatched <= blocks_dispatched + (waiting_before < remaining ? waiting_before : remaining);
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
	output wire [NUM_CONSUMERS - 1:0] consumer_read_ready;
	output wire [(DATA_BITS * NUM_CONSUMERS) - 1:0] consumer_read_data_flat;
	input wire [NUM_CONSUMERS - 1:0] consumer_write_valid;
	input wire [(ADDR_BITS * NUM_CONSUMERS) - 1:0] consumer_write_address_flat;
	input wire [(DATA_BITS * NUM_CONSUMERS) - 1:0] consumer_write_data_flat;
	output wire [NUM_CONSUMERS - 1:0] consumer_write_ready;
	output wire [NUM_CHANNELS - 1:0] mem_read_valid;
	output wire [(ADDR_BITS * NUM_CHANNELS) - 1:0] mem_read_address_flat;
	input wire [NUM_CHANNELS - 1:0] mem_read_ready;
	input wire [(DATA_BITS * NUM_CHANNELS) - 1:0] mem_read_data_flat;
	output wire [NUM_CHANNELS - 1:0] mem_write_valid;
	output wire [(ADDR_BITS * NUM_CHANNELS) - 1:0] mem_write_address_flat;
	output wire [(DATA_BITS * NUM_CHANNELS) - 1:0] mem_write_data_flat;
	input wire [NUM_CHANNELS - 1:0] mem_write_ready;
	generate
		if (NUM_CONSUMERS == NUM_CHANNELS) begin : bypass_1to1
			assign mem_read_valid = consumer_read_valid;
			assign mem_read_address_flat = consumer_read_address_flat;
			assign consumer_read_ready = mem_read_ready;
			assign consumer_read_data_flat = mem_read_data_flat;
			if (WRITE_ENABLE) begin : write_path
				assign mem_write_valid = consumer_write_valid;
				assign mem_write_address_flat = consumer_write_address_flat;
				assign mem_write_data_flat = consumer_write_data_flat;
				assign consumer_write_ready = mem_write_ready;
			end
			else begin : no_write_path
				assign mem_write_valid = {NUM_CHANNELS {1'b0}};
				assign mem_write_address_flat = {ADDR_BITS * NUM_CHANNELS {1'b0}};
				assign mem_write_data_flat = {DATA_BITS * NUM_CHANNELS {1'b0}};
				assign consumer_write_ready = {NUM_CONSUMERS {1'b0}};
			end
		end
		else begin : dynamic_arbitration
			wire [ADDR_BITS - 1:0] consumer_read_address [NUM_CONSUMERS - 1:0];
			reg [DATA_BITS - 1:0] consumer_read_data [NUM_CONSUMERS - 1:0];
			wire [ADDR_BITS - 1:0] consumer_write_address [NUM_CONSUMERS - 1:0];
			wire [DATA_BITS - 1:0] consumer_write_data [NUM_CONSUMERS - 1:0];
			reg [ADDR_BITS - 1:0] mem_read_address [NUM_CHANNELS - 1:0];
			wire [DATA_BITS - 1:0] mem_read_data [NUM_CHANNELS - 1:0];
			reg [ADDR_BITS - 1:0] mem_write_address [NUM_CHANNELS - 1:0];
			reg [DATA_BITS - 1:0] mem_write_data [NUM_CHANNELS - 1:0];
			reg [NUM_CONSUMERS - 1:0] consumer_read_ready_reg;
			reg [NUM_CONSUMERS - 1:0] consumer_write_ready_reg;
			reg [NUM_CHANNELS - 1:0] mem_read_valid_reg;
			reg [NUM_CHANNELS - 1:0] mem_write_valid_reg;
			assign consumer_read_ready = consumer_read_ready_reg;
			assign consumer_write_ready = consumer_write_ready_reg;
			assign mem_read_valid = mem_read_valid_reg;
			assign mem_write_valid = mem_write_valid_reg;
			genvar _gv_c_2;
			for (_gv_c_2 = 0; _gv_c_2 < NUM_CONSUMERS; _gv_c_2 = _gv_c_2 + 1) begin : unflatten_consumer
				localparam c = _gv_c_2;
				assign consumer_read_address[c] = consumer_read_address_flat[((c + 1) * ADDR_BITS) - 1:c * ADDR_BITS];
				assign consumer_write_address[c] = consumer_write_address_flat[((c + 1) * ADDR_BITS) - 1:c * ADDR_BITS];
				assign consumer_write_data[c] = consumer_write_data_flat[((c + 1) * DATA_BITS) - 1:c * DATA_BITS];
			end
			genvar _gv_m_1;
			for (_gv_m_1 = 0; _gv_m_1 < NUM_CHANNELS; _gv_m_1 = _gv_m_1 + 1) begin : unflatten_mem
				localparam m = _gv_m_1;
				assign mem_read_data[m] = mem_read_data_flat[((m + 1) * DATA_BITS) - 1:m * DATA_BITS];
			end
			genvar _gv_f_1;
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
			always @(posedge clk)
				if (reset) begin
					mem_read_valid_reg <= {NUM_CHANNELS {1'b0}};
					mem_write_valid_reg <= {NUM_CHANNELS {1'b0}};
					consumer_read_ready_reg <= {NUM_CONSUMERS {1'b0}};
					consumer_write_ready_reg <= {NUM_CONSUMERS {1'b0}};
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
									begin : sv2v_autoblock_1
										reg signed [SEL_WIDTH - 1:0] sv2v_tmp_cast;
										sv2v_tmp_cast = sel;
										current_consumer[i] <= sv2v_tmp_cast;
									end
									if (!sel_is_write) begin
										mem_read_valid_reg[i] <= 1'b1;
										mem_read_address[i] <= consumer_read_address[sel];
										controller_state[i] <= READ_WAITING;
									end
									else begin
										mem_write_valid_reg[i] <= 1'b1;
										mem_write_address[i] <= consumer_write_address[sel];
										mem_write_data[i] <= consumer_write_data[sel];
										controller_state[i] <= WRITE_WAITING;
									end
								end
							end
							READ_WAITING:
								if (mem_read_ready[i]) begin
									mem_read_valid_reg[i] <= 0;
									consumer_read_ready_reg[current_consumer[i]] <= 1;
									consumer_read_data[current_consumer[i]] <= mem_read_data[i];
									controller_state[i] <= READ_RELAYING;
								end
							WRITE_WAITING:
								if (mem_write_ready[i]) begin
									mem_write_valid_reg[i] <= 0;
									consumer_write_ready_reg[current_consumer[i]] <= 1;
									controller_state[i] <= WRITE_RELAYING;
								end
							READ_RELAYING:
								if (!consumer_read_valid[current_consumer[i]]) begin
									serving_next[current_consumer[i]] = 1'b0;
									consumer_read_ready_reg[current_consumer[i]] <= 0;
									controller_state[i] <= IDLE;
								end
							WRITE_RELAYING:
								if (!consumer_write_valid[current_consumer[i]]) begin
									serving_next[current_consumer[i]] = 1'b0;
									consumer_write_ready_reg[current_consumer[i]] <= 0;
									controller_state[i] <= IDLE;
								end
							default: controller_state[i] <= IDLE;
						endcase
					channel_serving_consumer <= serving_next;
				end
		end
	endgenerate
endmodule