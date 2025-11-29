`default_nettype none
`timescale 1ns/1ns

// BRANCH DIVERGENCE UNIT
// > Handles SIMT execution where threads take different paths
// > Maintains divergence stack for nested branches
// > Tracks active thread mask per warp
// > Manages reconvergence at post-dominator points
module branch_diverge #(
    parameter THREADS_PER_WARP = 8,
    parameter STACK_DEPTH = 8,            // Max nesting depth
    parameter PC_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Branch detection inputs
    input wire branch_instruction,         // Current instruction is a branch
    input wire [THREADS_PER_WARP-1:0] branch_taken,  // Which threads take branch
    input wire [PC_BITS-1:0] branch_target,  // Target PC if taken
    input wire [PC_BITS-1:0] fallthrough_pc, // PC if not taken
    input wire [PC_BITS-1:0] reconverge_pc,  // Post-dominator PC

    // Reconvergence detection
    input wire [PC_BITS-1:0] current_pc,   // Current program counter

    // Outputs
    output reg [THREADS_PER_WARP-1:0] active_mask,  // Currently active threads
    output reg [PC_BITS-1:0] next_pc,      // PC to execute
    output reg diverged,                    // Warp is currently diverged
    output reg stall                        // Stall while handling divergence
);
    // Divergence stack entry
    typedef struct packed {
        logic [THREADS_PER_WARP-1:0] mask;     // Threads to reactivate
        logic [PC_BITS-1:0] reconverge;         // Reconvergence point
        logic [PC_BITS-1:0] target_pc;          // PC for masked threads
        logic valid;
    } stack_entry_t;

    // Stack storage
    stack_entry_t diverge_stack [STACK_DEPTH-1:0];
    reg [$clog2(STACK_DEPTH)-1:0] stack_ptr;

    // Internal state
    reg [THREADS_PER_WARP-1:0] full_mask;  // All threads in warp
    reg executing_taken;                    // Currently executing taken path

    // Check for reconvergence
    wire at_reconverge = diverge_stack[stack_ptr > 0 ? stack_ptr - 1 : 0].valid &&
                         (current_pc == diverge_stack[stack_ptr > 0 ? stack_ptr - 1 : 0].reconverge);

    // Count active threads (for choosing path)
    integer i;
    reg [$clog2(THREADS_PER_WARP):0] taken_count, not_taken_count;
    always @(*) begin
        taken_count = 0;
        not_taken_count = 0;
        for (i = 0; i < THREADS_PER_WARP; i = i + 1) begin
            if (active_mask[i]) begin
                if (branch_taken[i])
                    taken_count = taken_count + 1;
                else
                    not_taken_count = not_taken_count + 1;
            end
        end
    end

    // Divergence occurs when some threads take, some don't
    wire will_diverge = branch_instruction && (taken_count > 0) && (not_taken_count > 0);
    wire all_take = branch_instruction && (not_taken_count == 0);
    wire none_take = branch_instruction && (taken_count == 0);

    integer j;
    always @(posedge clk) begin
        if (reset) begin
            // Initialize with all threads active
            active_mask <= {THREADS_PER_WARP{1'b1}};
            full_mask <= {THREADS_PER_WARP{1'b1}};
            stack_ptr <= 0;
            diverged <= 1'b0;
            stall <= 1'b0;
            next_pc <= {PC_BITS{1'b0}};
            executing_taken <= 1'b0;
            
            // Clear stack
            for (j = 0; j < STACK_DEPTH; j = j + 1) begin
                diverge_stack[j].mask <= {THREADS_PER_WARP{1'b0}};
                diverge_stack[j].reconverge <= {PC_BITS{1'b0}};
                diverge_stack[j].target_pc <= {PC_BITS{1'b0}};
                diverge_stack[j].valid <= 1'b0;
            end
        end else if (enable) begin
            stall <= 1'b0;

            // Check for reconvergence first
            if (at_reconverge && stack_ptr > 0) begin
                // Pop from stack and restore threads
                stack_ptr <= stack_ptr - 1;
                
                if (diverge_stack[stack_ptr - 1].mask != {THREADS_PER_WARP{1'b0}}) begin
                    // More threads to execute at different PC
                    active_mask <= diverge_stack[stack_ptr - 1].mask;
                    next_pc <= diverge_stack[stack_ptr - 1].target_pc;
                    // Clear the mask (will be handled)
                    diverge_stack[stack_ptr - 1].mask <= {THREADS_PER_WARP{1'b0}};
                    stall <= 1'b1;
                end else begin
                    // True reconvergence - restore all threads
                    active_mask <= full_mask;
                    diverged <= (stack_ptr > 1);  // Still diverged if nested
                end
            end
            // Handle branch instruction
            else if (branch_instruction) begin
                if (will_diverge) begin
                    // DIVERGENCE! Push to stack
                    if (stack_ptr < STACK_DEPTH) begin
                        // Push not-taken threads to execute later
                        diverge_stack[stack_ptr].mask <= active_mask & ~branch_taken;
                        diverge_stack[stack_ptr].reconverge <= reconverge_pc;
                        diverge_stack[stack_ptr].target_pc <= fallthrough_pc;
                        diverge_stack[stack_ptr].valid <= 1'b1;
                        stack_ptr <= stack_ptr + 1;
                        
                        // Execute taken path first (arbitrarily)
                        active_mask <= active_mask & branch_taken;
                        next_pc <= branch_target;
                        diverged <= 1'b1;
                        executing_taken <= 1'b1;
                        stall <= 1'b1;
                    end
                end
                else if (all_take) begin
                    // All active threads take branch - no divergence
                    next_pc <= branch_target;
                end
                else begin
                    // None take - continue to fallthrough
                    next_pc <= fallthrough_pc;
                end
            end
        end
    end

    // Debug outputs
    wire [$clog2(STACK_DEPTH)-1:0] debug_stack_depth = stack_ptr;
    wire [THREADS_PER_WARP-1:0] debug_active = active_mask;
endmodule

