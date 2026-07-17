`default_nettype none
`timescale 1ns/1ns

// COMPUTE CORE (SF16 Fixed-Point with Neural Network Support)
// > Handles processing 1 block at a time
// > Each core contains 1 fetcher, and per-thread: registers, ALU, FMA, Activation, LSU, PC
// > The GPU top level owns instruction decoding and passes decoded controls in.
// > Includes one 2x2 systolic array for accelerated matrix operations
// > Supports neural network operations: FMA for matmul, ACT for activation functions
// > Hierarchical design for improved physical synthesis

module core #(
    parameter DATA_MEM_ADDR_BITS = 19,       // 1 MiB total data memory: 2^19 x 16-bit
    parameter DATA_MEM_DATA_BITS = 16,       // SF16 fixed-point (16-bit)
    parameter PROGRAM_MEM_ADDR_BITS = 9,     // 512 instructions
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter THREADS_PER_BLOCK = 2,          // 2 threads per block
    parameter SYSTOLIC_SIZE = 2,              // 2x2 systolic array size
    parameter NUM_SYSTOLIC_ARRAYS = 1,        // One array per core
    parameter CACHE_SIZE = 2                 // Instruction cache entries (reserved)
) (
    input wire clk,
    input wire reset,

    // Kernel Execution
    input wire start,
    output wire done,

    // Block Metadata
    input wire [7:0] block_id,
    input wire [$clog2(THREADS_PER_BLOCK):0] thread_count,

    // Instruction decode boundary
    output wire [2:0] core_state_for_decode,
    output wire [15:0] instruction_for_decode,
    input wire [3:0] decoded_rd_address,
    input wire [3:0] decoded_rs_address,
    input wire [3:0] decoded_rt_address,
    input wire [2:0] decoded_nzp,
    input wire [7:0] decoded_immediate,
    input wire decoded_reg_write_enable,
    input wire decoded_mem_read_enable,
    input wire decoded_mem_write_enable,
    input wire decoded_nzp_write_enable,
    input wire [2:0] decoded_reg_input_mux,
    input wire [1:0] decoded_alu_arithmetic_mux,
    input wire decoded_alu_output_mux,
    input wire decoded_pc_mux,
    input wire decoded_fma_enable,
    input wire decoded_act_enable,
    input wire [1:0] decoded_act_func,
    input wire decoded_systolic_enable,
    input wire [1:0] decoded_systolic_op,
    input wire decoded_systolic_idx,
    input wire decoded_branch,
    input wire decoded_ret,

    // Program Memory
    output wire program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input wire program_mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    // Data Memory (16-bit SF16) - Flattened for synthesis
    output wire [THREADS_PER_BLOCK-1:0] data_mem_read_valid,
    output wire [DATA_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] data_mem_read_address_flat,
    input wire [THREADS_PER_BLOCK-1:0] data_mem_read_ready,
    input wire [DATA_MEM_DATA_BITS*THREADS_PER_BLOCK-1:0] data_mem_read_data_flat,
    output wire [THREADS_PER_BLOCK-1:0] data_mem_write_valid,
    output wire [DATA_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] data_mem_write_address_flat,
    output wire [DATA_MEM_DATA_BITS*THREADS_PER_BLOCK-1:0] data_mem_write_data_flat,
    input wire [THREADS_PER_BLOCK-1:0] data_mem_write_ready
);
    // Internal memory interface signals (unpacked for per-thread use)
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [THREADS_PER_BLOCK-1:0];

    // Unflatten input data from flat bus to per-thread
    genvar flat_idx;
    generate
        for (flat_idx = 0; flat_idx < THREADS_PER_BLOCK; flat_idx = flat_idx + 1) begin : unflatten_mem
            assign data_mem_read_data[flat_idx] = data_mem_read_data_flat[(flat_idx+1)*DATA_MEM_DATA_BITS-1 : flat_idx*DATA_MEM_DATA_BITS];
        end
    endgenerate

    // Flatten output buses using generate (parameterized)
    genvar out_idx;
    generate
        for (out_idx = 0; out_idx < THREADS_PER_BLOCK; out_idx = out_idx + 1) begin : flatten_out
            assign data_mem_read_address_flat[(out_idx+1)*DATA_MEM_ADDR_BITS-1 : out_idx*DATA_MEM_ADDR_BITS] = data_mem_read_address[out_idx];
            assign data_mem_write_address_flat[(out_idx+1)*DATA_MEM_ADDR_BITS-1 : out_idx*DATA_MEM_ADDR_BITS] = data_mem_write_address[out_idx];
            assign data_mem_write_data_flat[(out_idx+1)*DATA_MEM_DATA_BITS-1 : out_idx*DATA_MEM_DATA_BITS] = data_mem_write_data[out_idx];
        end
    endgenerate

    // State
    reg [2:0] core_state;
    reg [2:0] fetcher_state;
    reg [15:0] instruction;
    assign core_state_for_decode = core_state;
    assign instruction_for_decode = instruction;

    // Intermediate Signals (16-bit SF16)
    // Program counter uses full program memory address width
    reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] next_pc[THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] rs[THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] rt[THREADS_PER_BLOCK-1:0];
    wire [1:0] lsu_state[THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] lsu_out[THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] alu_out[THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] fma_out[THREADS_PER_BLOCK-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] act_out[THREADS_PER_BLOCK-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] systolic_out[THREADS_PER_BLOCK-1:0];
    
    // Flatten signals for scheduler (parameterized)
    reg [(2*THREADS_PER_BLOCK)-1:0] lsu_state_flat;
    reg [PROGRAM_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] next_pc_flat;
    
    integer lsu_idx;
    always @(*) begin
        for (lsu_idx = 0; lsu_idx < THREADS_PER_BLOCK; lsu_idx = lsu_idx + 1) begin
            lsu_state_flat[lsu_idx*2 +: 2] = lsu_state[lsu_idx];
            next_pc_flat[lsu_idx*PROGRAM_MEM_ADDR_BITS +: PROGRAM_MEM_ADDR_BITS] = next_pc[lsu_idx];
        end
    end
    
    // For FMA: accumulator input from destination register (direct combinational read)
    wire [DATA_MEM_DATA_BITS-1:0] rd_data[THREADS_PER_BLOCK-1:0];

    // ============================================
    // Fetcher (connects directly to external memory)
    fetcher #(
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS)
    ) fetcher_instance (
        .clk(clk),
        .reset(reset),
        .core_state(core_state),
        .current_pc(current_pc),
        .mem_read_valid(program_mem_read_valid),
        .mem_read_address(program_mem_read_address),
        .mem_read_ready(program_mem_read_ready),
        .mem_read_data(program_mem_read_data),
        .fetcher_state(fetcher_state),
        .instruction(instruction) 
    );

    // Stage 1: Pipeline decoded control signals to cut fanout RC delay
    reg [3:0]  pipe_rd_address;
    reg [3:0]  pipe_rs_address;
    reg [3:0]  pipe_rt_address;
    reg [2:0]  pipe_nzp;
    reg [7:0]  pipe_immediate;
    reg        pipe_reg_write_enable;
    reg        pipe_mem_read_enable;
    reg        pipe_mem_write_enable;
    reg        pipe_nzp_write_enable;
    reg [2:0]  pipe_reg_input_mux;
    reg [1:0]  pipe_alu_arithmetic_mux;
    reg        pipe_alu_output_mux;
    reg        pipe_pc_mux;
    reg        pipe_fma_enable;
    reg        pipe_act_enable;
    reg [1:0]  pipe_act_func;
    reg        pipe_systolic_enable;
    reg [1:0]  pipe_systolic_op;
    reg        pipe_systolic_idx;
    reg        pipe_ret;
    reg        pipe_branch;

    always @(posedge clk) begin
        if (reset) begin
            pipe_rd_address        <= 4'b0;
            pipe_rs_address        <= 4'b0;
            pipe_rt_address        <= 4'b0;
            pipe_nzp               <= 3'b0;
            pipe_immediate         <= 8'b0;
            pipe_reg_write_enable  <= 1'b0;
            pipe_mem_read_enable   <= 1'b0;
            pipe_mem_write_enable  <= 1'b0;
            pipe_nzp_write_enable  <= 1'b0;
            pipe_reg_input_mux     <= 3'b0;
            pipe_alu_arithmetic_mux<= 2'b0;
            pipe_alu_output_mux    <= 1'b0;
            pipe_pc_mux            <= 1'b0;
            pipe_fma_enable        <= 1'b0;
            pipe_act_enable        <= 1'b0;
            pipe_act_func          <= 2'b0;
            pipe_systolic_enable   <= 1'b0;
            pipe_systolic_op       <= 2'b0;
            pipe_systolic_idx      <= 1'b0;
            pipe_ret               <= 1'b0;
            pipe_branch            <= 1'b0;
        end else begin
            pipe_rd_address        <= decoded_rd_address;
            pipe_rs_address        <= decoded_rs_address;
            pipe_rt_address        <= decoded_rt_address;
            pipe_nzp               <= decoded_nzp;
            pipe_immediate         <= decoded_immediate;
            pipe_reg_write_enable  <= decoded_reg_write_enable;
            pipe_mem_read_enable   <= decoded_mem_read_enable;
            pipe_mem_write_enable  <= decoded_mem_write_enable;
            pipe_nzp_write_enable  <= decoded_nzp_write_enable;
            pipe_reg_input_mux     <= decoded_reg_input_mux;
            pipe_alu_arithmetic_mux<= decoded_alu_arithmetic_mux;
            pipe_alu_output_mux    <= decoded_alu_output_mux;
            pipe_pc_mux            <= decoded_pc_mux;
            pipe_fma_enable        <= decoded_fma_enable;
            pipe_act_enable        <= decoded_act_enable;
            pipe_act_func          <= decoded_act_func;
            pipe_systolic_enable   <= decoded_systolic_enable;
            pipe_systolic_op       <= decoded_systolic_op;
            pipe_systolic_idx      <= decoded_systolic_idx;
            pipe_ret               <= decoded_ret;
            pipe_branch            <= decoded_branch;
        end
    end

    // Branch divergence signals
    wire [THREADS_PER_BLOCK-1:0] branch_taken;  // Per-thread from PC units
    wire [PROGRAM_MEM_ADDR_BITS-1:0] branch_target;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] reconverge_pc;
    wire [THREADS_PER_BLOCK-1:0] active_mask;
    wire diverged;
    
    // Per-thread branch taken signals from PC units
    wire per_thread_branch_taken[THREADS_PER_BLOCK-1:0];
    
    // Flatten per-thread branch_taken to packed vector (parameterized)
    integer br_idx;
    reg [THREADS_PER_BLOCK-1:0] branch_taken_reg;
    always @(*) begin
        for (br_idx = 0; br_idx < THREADS_PER_BLOCK; br_idx = br_idx + 1) begin
            branch_taken_reg[br_idx] = per_thread_branch_taken[br_idx];
        end
    end
    assign branch_taken = branch_taken_reg;
    assign branch_target = {{(PROGRAM_MEM_ADDR_BITS-8){1'b0}}, pipe_immediate};  // Zero-extend 8-bit to 12-bit
    assign reconverge_pc = current_pc + 2;  // Simple reconvergence at fall-through + 1

    // Scheduler
    scheduler #(
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .ENABLE_BRANCH_DIVERGE(0)   // Disabled: saves ~300 cells; re-enable for divergent kernels
    ) scheduler_instance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .fetcher_state(fetcher_state),
        .core_state(core_state),
        .decoded_fma_enable(pipe_fma_enable),
        .decoded_ret(pipe_ret),
        .decoded_branch(pipe_branch),
        .branch_taken(branch_taken),
        .branch_target(branch_target),
        .reconverge_pc(reconverge_pc),
        .lsu_state_flat(lsu_state_flat),
        .current_pc(current_pc),
        .next_pc_flat(next_pc_flat),
        .active_mask(active_mask),
        .diverged(diverged),
        .done(done)
    );

    // Pipeline registers for register file outputs to break long combinational paths
    reg [DATA_MEM_DATA_BITS-1:0] pipe_rs [THREADS_PER_BLOCK-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] pipe_rt [THREADS_PER_BLOCK-1:0];
    reg [DATA_MEM_DATA_BITS-1:0] pipe_rd_data [THREADS_PER_BLOCK-1:0];

    always @(posedge clk) begin
        if (reset) begin
            for (integer t = 0; t < THREADS_PER_BLOCK; t = t + 1) begin
                pipe_rs[t] <= {DATA_MEM_DATA_BITS{1'b0}};
                pipe_rt[t] <= {DATA_MEM_DATA_BITS{1'b0}};
                pipe_rd_data[t] <= {DATA_MEM_DATA_BITS{1'b0}};
            end
        end else if (core_state == 3'b010) begin // DECODE state
            for (integer t = 0; t < THREADS_PER_BLOCK; t = t + 1) begin
                pipe_rs[t] <= rs[t];
                pipe_rt[t] <= rt[t];
                pipe_rd_data[t] <= rd_data[t];
            end
        end
    end

    // Per-thread compute units
    genvar i;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : threads
            // ALU (Integer arithmetic for indexing)
            alu #(
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) alu_instance (
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

            // Optimized FMA Unit (SF16 multiply-accumulate)
            fma #(
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) fma_instance (
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

            // Activation Unit
            activation #(
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) activation_instance (
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

            // Load/Store Unit
            lsu #(
                .ADDR_BITS(DATA_MEM_ADDR_BITS),
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) lsu_instance (
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

            // Register File (16-bit)
            registers #(
                .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
                .THREAD_ID(i),
                .DATA_BITS(DATA_MEM_DATA_BITS)
            ) register_instance (
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

            // Program Counter
            pc #(
                .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS)
            ) pc_instance (
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

    // ============================================
    // Systolic Array
    // SYS instruction op: 00=clear, 01=load weights, 10=compute, 11=read.
    // The first SYSTOLIC_SIZE threads provide rs/rt stream inputs; the first
    // SYSTOLIC_SIZE*SYSTOLIC_SIZE threads can read flattened result cells.
    // ============================================

    localparam [1:0] SYSTOLIC_OP_CLEAR   = 2'b00;
    localparam [1:0] SYSTOLIC_OP_LOAD    = 2'b01;
    localparam [1:0] SYSTOLIC_OP_COMPUTE = 2'b10;
    localparam int unsigned FMA_VISIBLE_LATENCY = 3;
    localparam int unsigned SYSTOLIC_DRAIN_CYCLES =
        SYSTOLIC_SIZE + FMA_VISIBLE_LATENCY;
    localparam int unsigned SYSTOLIC_RESULT_COUNT =
        SYSTOLIC_SIZE * SYSTOLIC_SIZE;

    wire systolic_exec = (core_state == 3'b101) && pipe_systolic_enable;
    wire systolic_clear_acc = systolic_exec && (pipe_systolic_op == SYSTOLIC_OP_CLEAR);
    wire systolic_load_weights = systolic_exec && (pipe_systolic_op == SYSTOLIC_OP_LOAD);
    wire systolic_compute_enable = systolic_exec && (pipe_systolic_op == SYSTOLIC_OP_COMPUTE);

    reg [SYSTOLIC_DRAIN_CYCLES-1:0] systolic_compute_drain;
    wire systolic_enable =
        systolic_clear_acc ||
        systolic_load_weights ||
        systolic_compute_enable ||
        (|systolic_compute_drain);

    always @(posedge clk) begin
        if (reset) begin
            systolic_compute_drain <= {SYSTOLIC_DRAIN_CYCLES{1'b0}};
        end else begin
            systolic_compute_drain[0] <= systolic_compute_enable;
            systolic_compute_drain[SYSTOLIC_DRAIN_CYCLES-1:1] <=
                systolic_compute_drain[SYSTOLIC_DRAIN_CYCLES-2:0];
        end
    end

    wire [DATA_MEM_DATA_BITS*SYSTOLIC_SIZE-1:0] systolic_a_inputs_flat [NUM_SYSTOLIC_ARRAYS-1:0];
    wire [DATA_MEM_DATA_BITS*SYSTOLIC_SIZE-1:0] systolic_b_inputs_flat [NUM_SYSTOLIC_ARRAYS-1:0];
    wire [DATA_MEM_DATA_BITS*SYSTOLIC_RESULT_COUNT-1:0] systolic_results_flat [NUM_SYSTOLIC_ARRAYS-1:0];
    wire [NUM_SYSTOLIC_ARRAYS-1:0] systolic_ready;

    // Distribute data across both arrays:
    // Array k maps inputs from threads k*SYSTOLIC_SIZE to (k+1)*SYSTOLIC_SIZE - 1.
    genvar arr_idx, elem_idx;
    generate
        for (arr_idx = 0; arr_idx < NUM_SYSTOLIC_ARRAYS; arr_idx = arr_idx + 1) begin : input_map
            for (elem_idx = 0; elem_idx < SYSTOLIC_SIZE; elem_idx = elem_idx + 1) begin : elem_map
                localparam int thread_idx = arr_idx * SYSTOLIC_SIZE + elem_idx;
                if (thread_idx < THREADS_PER_BLOCK) begin : active_thread
                    assign systolic_a_inputs_flat[arr_idx][elem_idx*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS] = pipe_rs[thread_idx];
                    assign systolic_b_inputs_flat[arr_idx][elem_idx*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS] = pipe_rt[thread_idx];
                end else begin : inactive_thread
                    assign systolic_a_inputs_flat[arr_idx][elem_idx*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS] = {DATA_MEM_DATA_BITS{1'b0}};
                    assign systolic_b_inputs_flat[arr_idx][elem_idx*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS] = {DATA_MEM_DATA_BITS{1'b0}};
                end
            end
        end
    endgenerate

    // Read logic: route outputs from the selected array to systolic_out
    integer systolic_result_idx;
    always @(*) begin
        for (systolic_result_idx = 0; systolic_result_idx < THREADS_PER_BLOCK; systolic_result_idx = systolic_result_idx + 1) begin
            if (systolic_result_idx < SYSTOLIC_RESULT_COUNT) begin
                if (pipe_systolic_idx < NUM_SYSTOLIC_ARRAYS) begin
                    systolic_out[systolic_result_idx] =
                        systolic_results_flat[pipe_systolic_idx][systolic_result_idx*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS];
                end else begin
                    systolic_out[systolic_result_idx] = {DATA_MEM_DATA_BITS{1'b0}};
                end
            end else begin
                systolic_out[systolic_result_idx] = {DATA_MEM_DATA_BITS{1'b0}};
            end
        end
    end

    genvar k;
    generate
        for (k = 0; k < NUM_SYSTOLIC_ARRAYS; k = k + 1) begin : systolic_arrays
            systolic_array #(
                .DATA_BITS(DATA_MEM_DATA_BITS),
                .ARRAY_SIZE(SYSTOLIC_SIZE),
                .PIPE_INTERVAL(SYSTOLIC_SIZE)
            ) systolic_array_inst (
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
