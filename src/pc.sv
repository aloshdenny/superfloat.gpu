`default_nettype none
`timescale 1ns/1ns

// PROGRAM COUNTER (SF16 Fixed-Point Compatible)
// > Calculates the next PC for each thread to update to (but currently we assume all threads
//   update to the same PC and don't support branch divergence)
// > Currently, each thread in each core has its own calculation for next PC
// > The NZP register value is set by the CMP instruction (based on >/=/< comparison) to 
//   initiate the BRnzp instruction for branching
module pc #(
    parameter DATA_MEM_DATA_BITS = 16,      // SF16 data width (16-bit)
    parameter PROGRAM_MEM_ADDR_BITS = 8     // Program memory address width (8-bit)
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads than block size, some PCs will be inactive

    // State
    input reg [2:0] core_state,

    // Control Signals
    input reg [2:0] decoded_nzp,
    input reg decoded_nzp_write_enable,
    input reg decoded_pc_mux, 

    // ALU Output - used for alu_out[2:0] to compare with NZP register
    // Now 16-bit for SF16, but we only use lower 3 bits for NZP flags
    input reg [2:0] alu_out,

    // Current & Next PCs
    input reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] next_pc,

    // Branch taken output - high when this thread takes a branch
    output wire branch_taken,

    // Full instruction for BR offset decoding (PC-relative imm9)
    input reg [8:0] instruction
);
    reg [2:0] nzp;

    // Branch taken when pc_mux is set and NZP condition matches
    assign branch_taken = enable && decoded_pc_mux && ((nzp & decoded_nzp) != 3'b0);

    // PC-relative branch target computation (imm9) with explicit sign-extension.
    // This avoids signedness pitfalls from part-selects after sv2v/iverilog lowering.
    // IMPORTANT: avoid 1'sd1 (1-bit signed literal == -1). Use an explicitly-sized +1.
    wire signed [PROGRAM_MEM_ADDR_BITS:0] pc_plus_one_s =
        $signed({1'b0, current_pc}) + $signed({{PROGRAM_MEM_ADDR_BITS{1'b0}}, 1'b1});
    localparam integer BR_OFF_W = PROGRAM_MEM_ADDR_BITS + 1;
    wire signed [BR_OFF_W-1:0] br_off9_s = $signed({{(BR_OFF_W-9){instruction[8]}}, instruction[8:0]});
    wire signed [PROGRAM_MEM_ADDR_BITS:0] br_target_s = pc_plus_one_s + br_off9_s;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] br_target = (PROGRAM_MEM_ADDR_BITS)'(br_target_s);

    assign next_pc = (decoded_pc_mux && ((nzp & decoded_nzp) != 3'b0)) ? br_target : (current_pc + 1'b1);

    always @(posedge clk) begin
        if (reset) begin
            nzp <= 3'b0;
        end else if (enable) begin
            // Store NZP when core_state = UPDATE   
            if (core_state == 3'b110) begin 
                // Write to NZP register on CMP instruction
                // NZP flags are in the lower 3 bits of alu_out
                if (decoded_nzp_write_enable) begin
                    nzp <= alu_out;
                end
            end      
        end
    end

endmodule
