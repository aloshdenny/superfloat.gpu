`default_nettype none
`timescale 1ns/1ns

// SCHEDULER
// > Manages the entire control flow of a single compute core processing 1 block
// 1. FETCH - Retrieve instruction at current program counter (PC) from program memory
// 2. DECODE - Decode the instruction into the relevant control signals
// 3. REQUEST - If we have an instruction that accesses memory, trigger the async memory requests from LSUs
// 4. WAIT - Wait for all async memory requests to resolve (if applicable)
// 5. EXECUTE - Execute computations on retrieved data from registers / memory
// 6. UPDATE - Update register values (including NZP register) and program counter
// > Each core has it's own scheduler where multiple threads can be processed with
//   the same control flow at once.
// > Branch divergence handled by branch_diverge unit
module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire start,
    
    // Control Signals
    input wire decoded_fma_enable,
    input wire decoded_ret,
    
    // Branch control (new)
    input wire decoded_branch,
    input wire [THREADS_PER_BLOCK-1:0] branch_taken,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] branch_target,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] reconverge_pc,

    // Memory Access State
    input wire [2:0] fetcher_state,
    input wire [(2*THREADS_PER_BLOCK)-1:0] lsu_state_flat,

    // Current & Next PC
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    input wire [PROGRAM_MEM_ADDR_BITS*THREADS_PER_BLOCK-1:0] next_pc_flat,
    
    // Active thread mask (from divergence unit)
    output wire [THREADS_PER_BLOCK-1:0] active_mask,
    output wire diverged,

    // Execution State
    output reg [2:0] core_state,
    output reg done
);
    // Unflatten inputs
    wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0];
    wire [PROGRAM_MEM_ADDR_BITS-1:0] next_pc [THREADS_PER_BLOCK-1:0];

    genvar sch_idx;
    generate
        for (sch_idx = 0; sch_idx < THREADS_PER_BLOCK; sch_idx = sch_idx + 1) begin : unflatten_sch
            assign lsu_state[sch_idx] = lsu_state_flat[(sch_idx+1)*2-1 : sch_idx*2];
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
    
    // Check if any LSU is waiting
    reg any_lsu_waiting;
    integer i;

    // Some execution units are internally pipelined and require >1 EXECUTE cycle
    // for the result to become valid for WRITEBACK.
    reg fma_execute_second_cycle;
    
    // Branch divergence unit
    wire [PROGRAM_MEM_ADDR_BITS-1:0] diverge_next_pc;
    wire diverge_stall;
    
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
    
    always @(*) begin
        any_lsu_waiting = 1'b0;
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
            // Make sure no lsu_state = REQUESTING or WAITING
            if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10) begin
                any_lsu_waiting = 1'b1;
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
                    // Decode is synchronous so we move on after one cycle
                    core_state <= REQUEST;
                end
                REQUEST: begin 
                    // Request is synchronous so we move on after one cycle
                    core_state <= WAIT;
                end
                WAIT: begin
                    // If no LSU is waiting for a response, move onto the next stage
                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
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
                        // Use divergence-aware next PC
                        current_pc <= diverged ? diverge_next_pc : next_pc[THREADS_PER_BLOCK-1];

                        // Update is synchronous so we move on after one cycle
                        core_state <= FETCH;
                    end
                end
                DONE: begin 
                    // no-op
                end
            endcase
        end
    end
endmodule
