`default_nettype none
`timescale 1ns/1ns

// SCHEDULER
// > Manages the entire control flow of a single compute core processing 1 block
// 1. FETCH - Retrieve instruction at current program counter (PC) from program memory
// 2. DECODE - Decode the instruction into the relevant control signals
// 3. REQUEST - If we have an instruction that accesses memory, trigger the async memory requests from LSUs
// 4. WAIT - Wait for all async memory requests to resolve (if applicable)
//    REQUEST and WAIT are skipped by instructions that need neither (decoded_staged)
// 5. EXECUTE - Execute computations on retrieved data from registers / memory
// 6. UPDATE - Update register values (including NZP register) and program counter
// > Each core has it's own scheduler where multiple threads can be processed with
//   the same control flow at once.
// > Branch divergence handled by branch_diverge unit
module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
    parameter NUM_LSUS = THREADS_PER_BLOCK,     // LSUs whose states gate WAIT
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter ENABLE_BRANCH_DIVERGE = 0  // Set 1 to synthesize divergence stack
) (
    input wire clk,
    input wire reset,
    input wire start,
    
    // Control Signals
    input wire decoded_fma_enable,
    input wire decoded_staged,           // the instruction in DECODE uses REQUEST/WAIT (decoder output)
    input wire decoded_hold,             // the instruction in DECODE must wait there (a result is not ready)
    input wire decoded_ret,
    
    // Branch control (new)
    input wire decoded_branch,
    input wire [THREADS_PER_BLOCK-1:0] branch_taken,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] branch_target,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] reconverge_pc,

    // Memory Access State
    input wire [2:0] fetcher_state,
    input wire fetch_ahead_hit,          // UPDATE: the next instruction is already fetched (fetcher.sv)
    input wire [(2*NUM_LSUS)-1:0] lsu_state_flat,
    input wire [NUM_LSUS-1:0] lsu_answer,             // each LSU's memory answer this cycle (read or write ready)
    input wire pipe_mem_op,                           // the instruction is a load or store (EXECUTE has nothing to do)
    input wire pipe_mem_pair,                         // an LDR pair: EXECUTE writes the second register

    // Current & Next PC
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] update_pc,   // the PC UPDATE moves to
    input wire [PROGRAM_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] next_pc_flat,
    
    // Active thread mask (from divergence unit)
    output wire [THREADS_PER_BLOCK-1:0] active_mask,
    output wire diverged,

    // Execution State
    output reg [2:0] core_state,
    output reg done
);
    // Unflatten inputs
    wire [1:0] lsu_state [NUM_LSUS-1:0];
    wire [PROGRAM_MEM_ADDR_BITS-1:0] next_pc [THREADS_PER_BLOCK-1:0];

    genvar sch_idx;
    generate
        for (sch_idx = 0; sch_idx < NUM_LSUS; sch_idx = sch_idx + 1) begin : unflatten_lsu
            assign lsu_state[sch_idx] = lsu_state_flat[(sch_idx+1)*2-1 : sch_idx*2];
        end
        for (sch_idx = 0; sch_idx < THREADS_PER_BLOCK; sch_idx = sch_idx + 1) begin : unflatten_sch
            assign next_pc[sch_idx] = next_pc_flat[(sch_idx+1)*PROGRAM_MEM_ADDR_BITS-1 : sch_idx*PROGRAM_MEM_ADDR_BITS];
        end
    endgenerate

    localparam IDLE = 3'b000, // Waiting to start
        FETCH = 3'b001,       // Fetch instructions from program memory
        DECODE = 3'b010,      // Decode instructions into control signals
        REQUEST = 3'b011,     // Request data from registers or memory
        WAIT = 3'b100,        // Wait for response from memory if necessary
        EXECUTE = 3'b101,     // Execute ALU and PC calculations
        UPDATE = 3'b110,      // Update registers, NZP, and PC
        DONE = 3'b111;        // Done executing this block
    
    // Check if any LSU is waiting, and whether every one is answered by the
    // end of this cycle (its data is then registered for UPDATE)
    reg any_lsu_waiting;
    reg lsus_done_next;
    integer i;

    // Some execution units are internally pipelined and require >1 EXECUTE cycle
    // for the result to become valid for WRITEBACK.
    reg fma_execute_second_cycle;
    
    // Branch divergence unit
    // Set ENABLE_BRANCH_DIVERGE=0 to remove ~300 cells for non-divergent workloads.
    wire [PROGRAM_MEM_ADDR_BITS-1:0] diverge_next_pc;
    wire diverge_stall;
    
    generate
        if (ENABLE_BRANCH_DIVERGE) begin : gen_branch_diverge
            branch_diverge #(
                .THREADS_PER_WARP(THREADS_PER_BLOCK),
                .STACK_DEPTH(2),
                .PC_BITS(PROGRAM_MEM_ADDR_BITS)
            ) branch_diverge_inst (
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
        end else begin : gen_no_diverge
            // Tie off: all threads always active, no divergence, no stall
            assign active_mask    = {THREADS_PER_BLOCK{1'b1}};
            assign diverged       = 1'b0;
            assign diverge_stall  = 1'b0;
            assign diverge_next_pc = {PROGRAM_MEM_ADDR_BITS{1'b0}};
        end
    endgenerate
    
    assign update_pc = diverged ? diverge_next_pc : next_pc[0];

    always @(*) begin
        any_lsu_waiting = 1'b0;
        lsus_done_next  = 1'b1;
        for (i = 0; i < NUM_LSUS; i = i + 1) begin
            // An LSU still waiting for memory (2'b01 is unused)
            if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10) begin
                any_lsu_waiting = 1'b1;
                if (!lsu_answer[i]) lsus_done_next = 1'b0;
            end
        end
    end
    
    always @(posedge clk) begin 
        if (reset) begin
            current_pc <= 0;
            core_state <= IDLE;
            done <= 0;
            fma_execute_second_cycle <= 1'b0;
        end else begin 
            case (core_state)
                IDLE: begin
                    // Here after reset (before kernel is launched, or after previous block has been processed)
                    if (start) begin 
                        // Start by fetching the next instruction for this block based on PC
                        core_state <= FETCH;
                        fma_execute_second_cycle <= 1'b0;
                    end
                end
                FETCH: begin 
                    // Move on once fetcher_state = FETCHED
                    if (fetcher_state == 3'b010) begin 
                        core_state <= DECODE;
                    end
                end
                DECODE: begin
                    // Operands are captured at the end of DECODE. REQUEST/WAIT
                    // serve loads and stores and are pipeline stages of the
                    // longer units (see core.sv); everything else goes
                    // straight to EXECUTE.
                    if (!decoded_hold)
                        core_state <= decoded_staged ? REQUEST : EXECUTE;
                    fma_execute_second_cycle <= 1'b0;
                end
                REQUEST: begin 
                    // Request is synchronous so we move on after one cycle
                    core_state <= WAIT;
                end
                WAIT: begin
                    // Leave in the cycle the last answer arrives. A load or
                    // store has nothing to EXECUTE: its data is registered in
                    // the LSU for UPDATE. An LDR pair writes its second
                    // register in EXECUTE.
                    if (lsus_done_next) begin
                        core_state <= (pipe_mem_op && !pipe_mem_pair) ? UPDATE : EXECUTE;
                        fma_execute_second_cycle <= 1'b0;
                    end
                end
                EXECUTE: begin
                    // FMA is internally pipelined and needs two EXECUTE cycles.
                    if (decoded_fma_enable && !fma_execute_second_cycle) begin
                        fma_execute_second_cycle <= 1'b1;
                        core_state <= EXECUTE;
                    end else begin
                        fma_execute_second_cycle <= 1'b0;
                        core_state <= UPDATE;
                    end
                end
                UPDATE: begin 
                    if (decoded_ret) begin 
                        // If we reach a RET instruction, this block is done executing
                        done <= 1;
                        core_state <= DONE;
                    end else if (diverge_stall) begin
                        // Wait for divergence handling to complete
                        core_state <= UPDATE;
                    end else begin 
                        // Use divergence-aware next PC. Without divergence all active
                        // threads agree; thread 0 is active in every dispatched block,
                        // including a partial last block where high threads are disabled.
                        current_pc <= update_pc;

                        // Straight to DECODE when the fetcher already has the
                        // next instruction, else fetch it.
                        core_state <= fetch_ahead_hit ? DECODE : FETCH;
                    end
                end
                DONE: begin 
                    // no-op
                end
            endcase
        end
    end
endmodule
