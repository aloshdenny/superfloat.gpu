`default_nettype none
`timescale 1ns/1ns

// REGISTER FILE
// > Each thread within each core has its own register file with 13 free registers and 3 read-only registers
// > Read-only registers hold the familiar %blockIdx, %blockDim, and %threadIdx values critical to SIMD
// > All registers are 16-bit to support Q1.15 fixed-point format
module registers #(
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0,
    parameter DATA_BITS = 16  // Q1.15 fixed-point width
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads than block size, some registers will be inactive

    // Kernel Execution
    input reg [7:0] block_id,

    // State
    input reg [2:0] core_state,

    // Instruction Signals
    input reg [3:0] decoded_rd_address,
    input reg [3:0] decoded_rs_address,
    input reg [3:0] decoded_rt_address,

    // Control Signals
    input reg decoded_reg_write_enable,
    input reg [2:0] decoded_reg_input_mux,  // 3-bit mux: 000=ALU, 001=MEM, 010=CONST, 011=FMA, 100=ACT
    input reg [7:0] decoded_immediate,      // 8-bit immediate from instruction

    // Thread Unit Outputs
    input reg [DATA_BITS-1:0] alu_out,
    input reg [DATA_BITS-1:0] lsu_out,
    input reg [DATA_BITS-1:0] fma_out,      // FMA unit output
    input reg [DATA_BITS-1:0] act_out,      // Activation unit output

    // Register Outputs (Q1.15)
    output reg [DATA_BITS-1:0] rs,
    output reg [DATA_BITS-1:0] rt
);
    // Register input source selection (3-bit)
    localparam [2:0] MUX_ALU = 3'b000,      // ALU output (ADD, SUB, MUL, DIV)
                     MUX_MEMORY = 3'b001,    // LSU output (LDR)
                     MUX_CONSTANT = 3'b010,  // Immediate constant (CONST)
                     MUX_FMA = 3'b011,       // FMA output (FMA instruction)
                     MUX_ACT = 3'b100;       // Activation output (ACT instruction)

    // 16 registers per thread (13 free registers and 3 read-only registers)
    // All registers are 16-bit for Q1.15 fixed-point
    reg [DATA_BITS-1:0] registers[15:0];

    // Sign-extend 8-bit immediate to 16-bit
    wire [DATA_BITS-1:0] immediate_extended;
    assign immediate_extended = {{8{decoded_immediate[7]}}, decoded_immediate};

    always @(posedge clk) begin
        if (reset) begin
            // Empty rs, rt
            rs <= {DATA_BITS{1'b0}};
            rt <= {DATA_BITS{1'b0}};
            // Initialize all free registers to zero
            registers[0] <= {DATA_BITS{1'b0}};
            registers[1] <= {DATA_BITS{1'b0}};
            registers[2] <= {DATA_BITS{1'b0}};
            registers[3] <= {DATA_BITS{1'b0}};
            registers[4] <= {DATA_BITS{1'b0}};
            registers[5] <= {DATA_BITS{1'b0}};
            registers[6] <= {DATA_BITS{1'b0}};
            registers[7] <= {DATA_BITS{1'b0}};
            registers[8] <= {DATA_BITS{1'b0}};
            registers[9] <= {DATA_BITS{1'b0}};
            registers[10] <= {DATA_BITS{1'b0}};
            registers[11] <= {DATA_BITS{1'b0}};
            registers[12] <= {DATA_BITS{1'b0}};
            // Initialize read-only registers (stored as 16-bit but contain integer values)
            registers[13] <= {DATA_BITS{1'b0}};                                    // %blockIdx (set later)
            registers[14] <= {{(DATA_BITS-8){1'b0}}, THREADS_PER_BLOCK[7:0]};     // %blockDim
            registers[15] <= {{(DATA_BITS-8){1'b0}}, THREAD_ID[7:0]};             // %threadIdx
        end else if (enable) begin 
            // Update block_id when a new block is issued from dispatcher
            registers[13] <= {{(DATA_BITS-8){1'b0}}, block_id};
            
            // Fill rs/rt when core_state = REQUEST
            if (core_state == 3'b011) begin 
                rs <= registers[decoded_rs_address];
                rt <= registers[decoded_rt_address];
            end

            // Store rd when core_state = UPDATE
            if (core_state == 3'b110) begin 
                // Only allow writing to R0 - R12
                if (decoded_reg_write_enable && decoded_rd_address < 13) begin
                    case (decoded_reg_input_mux)
                        MUX_ALU: begin 
                            // ADD, SUB, MUL, DIV (integer arithmetic from ALU)
                            registers[decoded_rd_address] <= alu_out;
                        end
                        MUX_MEMORY: begin 
                            // LDR (16-bit from memory)
                            registers[decoded_rd_address] <= lsu_out;
                        end
                        MUX_CONSTANT: begin 
                            // CONST (8-bit immediate sign-extended to 16-bit)
                            registers[decoded_rd_address] <= immediate_extended;
                        end
                        MUX_FMA: begin 
                            // FMA (Q1.15 Fused Multiply-Add result)
                            registers[decoded_rd_address] <= fma_out;
                        end
                        MUX_ACT: begin 
                            // ACT (Activation function result)
                            registers[decoded_rd_address] <= act_out;
                        end
                        default: begin
                            registers[decoded_rd_address] <= alu_out;
                        end
                    endcase
                end
            end
        end
    end
endmodule
