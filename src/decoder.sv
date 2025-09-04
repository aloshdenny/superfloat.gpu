`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION DECODER
// > Decodes an instruction into the control signals necessary to execute it
// > Each core has its own decoder
// > ISA: Integer ops (ADD/SUB/MUL/DIV) for indexing, FMA/ACT for Q1.15 neural network operations
module decoder (
    input wire clk,
    input wire reset,

    input reg [2:0] core_state,
    input reg [15:0] instruction,
    
    // Instruction Signals
    output reg [3:0] decoded_rd_address,
    output reg [3:0] decoded_rs_address,
    output reg [3:0] decoded_rt_address,
    output reg [2:0] decoded_nzp,
    output reg [7:0] decoded_immediate,
    
    // Control Signals
    output reg decoded_reg_write_enable,           // Enable writing to a register
    output reg decoded_mem_read_enable,            // Enable reading from memory
    output reg decoded_mem_write_enable,           // Enable writing to memory
    output reg decoded_nzp_write_enable,           // Enable writing to NZP register
    output reg [2:0] decoded_reg_input_mux,        // Select input to register (000=ALU, 001=MEM, 010=CONST, 011=FMA, 100=ACT)
    output reg [1:0] decoded_alu_arithmetic_mux,   // Select arithmetic operation
    output reg decoded_alu_output_mux,             // Select operation in ALU
    output reg decoded_pc_mux,                     // Select source of next PC
    output reg decoded_fma_enable,                 // Enable FMA operation
    output reg decoded_act_enable,                 // Enable Activation unit
    output reg [1:0] decoded_act_func,             // Activation function (00=none, 01=ReLU, 10=LeakyReLU, 11=ClippedReLU)

    // Return (finished executing thread)
    output reg decoded_ret
);
    // Instruction opcodes
    // Integer operations for indexing/addressing, Q1.15 via FMA/ACT for neural network operations
    localparam NOP   = 4'b0000,  // No operation
        BRnzp        = 4'b0001,  // Branch on NZP condition
        CMP          = 4'b0010,  // Compare (integer)
        ADD          = 4'b0011,  // Integer add (for indexing)
        SUB          = 4'b0100,  // Integer subtract (for indexing)
        MUL          = 4'b0101,  // Integer multiply (for indexing)
        DIV          = 4'b0110,  // Integer divide (for indexing: row = i / N)
        LDR          = 4'b0111,  // Load 16-bit value from memory
        STR          = 4'b1000,  // Store 16-bit value to memory
        CONST        = 4'b1001,  // Load 8-bit immediate (sign-extended to 16-bit)
        FMA          = 4'b1010,  // Q1.15 Fused multiply-add: Rd = (Rs * Rt) + Rd (for matmul)
        ACT          = 4'b1011,  // Activation: Rd = act_func(Rs + Rt) where Rt is bias
        RET          = 4'b1111;  // Return (end thread execution)

    always @(posedge clk) begin 
        if (reset) begin 
            decoded_rd_address <= 0;
            decoded_rs_address <= 0;
            decoded_rt_address <= 0;
            decoded_immediate <= 0;
            decoded_nzp <= 0;
            decoded_reg_write_enable <= 0;
            decoded_mem_read_enable <= 0;
            decoded_mem_write_enable <= 0;
            decoded_nzp_write_enable <= 0;
            decoded_reg_input_mux <= 0;
            decoded_alu_arithmetic_mux <= 0;
            decoded_alu_output_mux <= 0;
            decoded_pc_mux <= 0;
            decoded_fma_enable <= 0;
            decoded_act_enable <= 0;
            decoded_act_func <= 0;
            decoded_ret <= 0;
        end else begin 
            // Decode when core_state = DECODE
            if (core_state == 3'b010) begin 
                // Get instruction signals from instruction every time
                decoded_rd_address <= instruction[11:8];
                decoded_rs_address <= instruction[7:4];
                decoded_rt_address <= instruction[3:0];
                decoded_immediate <= instruction[7:0];
                decoded_nzp <= instruction[11:9];

                // Control signals reset on every decode and set conditionally by instruction
                decoded_reg_write_enable <= 0;
                decoded_mem_read_enable <= 0;
                decoded_mem_write_enable <= 0;
                decoded_nzp_write_enable <= 0;
                decoded_reg_input_mux <= 0;
                decoded_alu_arithmetic_mux <= 0;
                decoded_alu_output_mux <= 0;
                decoded_pc_mux <= 0;
                decoded_fma_enable <= 0;
                decoded_act_enable <= 0;
                decoded_act_func <= 0;
                decoded_ret <= 0;

                // Set the control signals for each instruction
                case (instruction[15:12])
                    NOP: begin 
                        // No operation
                    end
                    BRnzp: begin 
                        decoded_pc_mux <= 1;
                    end
                    CMP: begin 
                        // Compare: signed integer comparison sets NZP flags
                        decoded_alu_output_mux <= 1;
                        decoded_nzp_write_enable <= 1;
                    end
                    ADD: begin 
                        // Integer addition (for indexing and address calculations)
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 3'b000;  // ALU output
                        decoded_alu_arithmetic_mux <= 2'b00;
                    end
                    SUB: begin 
                        // Integer subtraction (for indexing)
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 3'b000;  // ALU output
                        decoded_alu_arithmetic_mux <= 2'b01;
                    end
                    MUL: begin 
                        // Integer multiplication (for indexing)
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 3'b000;  // ALU output
                        decoded_alu_arithmetic_mux <= 2'b10;
                    end
                    DIV: begin 
                        // Integer division (for indexing: row = i / N, col = i % N)
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 3'b000;  // ALU output
                        decoded_alu_arithmetic_mux <= 2'b11;
                    end
                    LDR: begin 
                        // Load 16-bit value from memory
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 3'b001;  // Memory output
                        decoded_mem_read_enable <= 1;
                    end
                    STR: begin 
                        // Store 16-bit value to memory
                        decoded_mem_write_enable <= 1;
                    end
                    CONST: begin 
                        // Load 8-bit immediate, sign-extended to 16-bit
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 3'b010;  // Constant/immediate
                    end
                    FMA: begin 
                        // Q1.15 Fused Multiply-Add: Rd = (Rs * Rt) + Rd
                        // Uses FMA unit for Q1.15 matrix multiply-accumulate
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 3'b011;  // FMA output
                        decoded_fma_enable <= 1;
                    end
                    ACT: begin
                        // Activation: Rd = act_func(Rs + Rt) where Rt is bias
                        // instruction[9:8] encodes activation function
                        // 00=none, 01=ReLU, 10=LeakyReLU, 11=ClippedReLU
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 3'b100;  // Activation output
                        decoded_act_enable <= 1;
                        decoded_act_func <= instruction[9:8];
                    end
                    RET: begin 
                        // Return: signal thread execution complete
                        decoded_ret <= 1;
                    end
                endcase
            end
        end
    end
endmodule
