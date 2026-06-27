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
    // Divergence stack - separate arrays for each field (Yosys compatible)
    reg [THREADS_PER_WARP-1:0] stack_mask [0:STACK_DEPTH-1];
    reg [PC_BITS-1:0] stack_reconverge [0:STACK_DEPTH-1];
    reg [PC_BITS-1:0] stack_target_pc [0:STACK_DEPTH-1];
    reg [STACK_DEPTH-1:0] stack_valid;
    
    reg [$clog2(STACK_DEPTH+1)-1:0] stack_ptr;

    // Internal state
    reg [THREADS_PER_WARP-1:0] full_mask;  // All threads in warp

    // Previous stack entry index (clamped)
    localparam IDX_BITS = $clog2(STACK_DEPTH);
    wire [$clog2(STACK_DEPTH+1)-1:0] prev_ptr = (stack_ptr > 0) ? stack_ptr - 1 : 0;
    
    // Check for reconvergence
    wire at_reconverge = (32'(stack_ptr) > 0) && stack_valid[IDX_BITS'(prev_ptr)] && (current_pc == stack_reconverge[IDX_BITS'(prev_ptr)]);

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

    integer j;
    always @(posedge clk) begin
        if (reset) begin
            // Initialize with all threads active
            active_mask <= {THREADS_PER_WARP{1'b1}};
            full_mask <= {THREADS_PER_WARP{1'b1}};
            stack_ptr <= 0;
            stack_valid <= {STACK_DEPTH{1'b0}};
            diverged <= 1'b0;
            stall <= 1'b0;
            next_pc <= {PC_BITS{1'b0}};
            
            // Clear stack arrays
            for (j = 0; j < STACK_DEPTH; j = j + 1) begin
                stack_mask[j] <= {THREADS_PER_WARP{1'b0}};
                stack_reconverge[j] <= {PC_BITS{1'b0}};
                stack_target_pc[j] <= {PC_BITS{1'b0}};
            end
        end else if (enable) begin
            stall <= 1'b0;

            // Check for reconvergence first
            if (at_reconverge && stack_ptr > 0) begin
                // Pop from stack and restore threads
                stack_ptr <= stack_ptr - 1;
                
                if (stack_mask[IDX_BITS'(prev_ptr)] != {THREADS_PER_WARP{1'b0}}) begin
                    // More threads to execute at different PC
                    active_mask <= stack_mask[IDX_BITS'(prev_ptr)];
                    next_pc <= stack_target_pc[IDX_BITS'(prev_ptr)];
                    // Clear the mask (will be handled)
                    stack_mask[IDX_BITS'(prev_ptr)] <= {THREADS_PER_WARP{1'b0}};
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
                    if (32'(stack_ptr) < 32'(STACK_DEPTH)) begin
                        // Push not-taken threads to execute later
                        stack_mask[IDX_BITS'(stack_ptr)] <= active_mask & ~branch_taken;
                        stack_reconverge[IDX_BITS'(stack_ptr)] <= reconverge_pc;
                        stack_target_pc[IDX_BITS'(stack_ptr)] <= fallthrough_pc;
                        stack_valid[IDX_BITS'(stack_ptr)] <= 1'b1;
                        stack_ptr <= stack_ptr + 1;
                        
                        // Execute taken path first (arbitrarily)
                        active_mask <= active_mask & branch_taken;
                        next_pc <= branch_target;
                        diverged <= 1'b1;
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

endmodule

