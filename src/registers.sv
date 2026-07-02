`default_nettype none
`timescale 1ns/1ns

// REGISTER FILE
// > Each thread within each core has its own register file with 13 free registers and 3 read-only registers
// > Read-only registers hold the familiar %blockIdx, %blockDim, and %threadIdx values critical to SIMD
// > All registers are 16-bit to support SF16 fixed-point format
module registers #(
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0,
    parameter DATA_BITS = 16  // SF16 fixed-point width
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
    input reg [3:0] write_rd_address,

    // Control Signals
    input reg decoded_reg_write_enable,
    input reg [2:0] decoded_reg_input_mux,  // 3-bit mux: 000=ALU, 001=MEM, 010=CONST, 011=FMA, 100=ACT, 101=SYS
    input reg [7:0] decoded_immediate,      // 8-bit immediate from instruction

    // Thread Unit Outputs
    input reg [DATA_BITS-1:0] alu_out,
    input reg [DATA_BITS-1:0] lsu_out,
    input reg [DATA_BITS-1:0] fma_out,      // FMA unit output
    input reg [DATA_BITS-1:0] act_out,      // Activation unit output
    input reg [DATA_BITS-1:0] systolic_out, // Systolic array result output

    // Register Outputs (SF16)
    output reg [DATA_BITS-1:0] rs,
    output reg [DATA_BITS-1:0] rt,
    output reg [DATA_BITS-1:0] rd_data
);
    // Register input source selection (3-bit)
    localparam [2:0] MUX_ALU = 3'b000,      // ALU output (ADD, SUB, MUL, DIV)
                     MUX_MEMORY = 3'b001,    // LSU output (LDR)
                     MUX_CONSTANT = 3'b010,  // Immediate constant (CONST)
                     MUX_FMA = 3'b011,       // FMA output (FMA instruction)
                     MUX_ACT = 3'b100,       // Activation output (ACT instruction)
                     MUX_SYSTOLIC = 3'b101;  // Systolic array result (SYS.READ)

    // 13 free registers (R0-R12). Read-only registers (R13-R15) are bypassed.
    // All registers are 16-bit for SF16 fixed-point
    reg [DATA_BITS-1:0] registers[12:0];

    // Combinational register reads (used by LSU/ALU/FMA/ACT).
    always @(*) begin
        case (decoded_rs_address)
            4'd0:  rs = registers[0];
            4'd1:  rs = registers[1];
            4'd2:  rs = registers[2];
            4'd3:  rs = registers[3];
            4'd4:  rs = registers[4];
            4'd5:  rs = registers[5];
            4'd6:  rs = registers[6];
            4'd7:  rs = registers[7];
            4'd8:  rs = registers[8];
            4'd9:  rs = registers[9];
            4'd10: rs = registers[10];
            4'd11: rs = registers[11];
            4'd12: rs = registers[12];
            4'd13: rs = {{(DATA_BITS-8){1'b0}}, block_id};
            4'd14: rs = {{(DATA_BITS-8){1'b0}}, THREADS_PER_BLOCK[7:0]};
            4'd15: rs = {{(DATA_BITS-8){1'b0}}, THREAD_ID[7:0]};
            default: rs = {DATA_BITS{1'b0}};
        endcase
    end

    always @(*) begin
        case (decoded_rt_address)
            4'd0:  rt = registers[0];
            4'd1:  rt = registers[1];
            4'd2:  rt = registers[2];
            4'd3:  rt = registers[3];
            4'd4:  rt = registers[4];
            4'd5:  rt = registers[5];
            4'd6:  rt = registers[6];
            4'd7:  rt = registers[7];
            4'd8:  rt = registers[8];
            4'd9:  rt = registers[9];
            4'd10: rt = registers[10];
            4'd11: rt = registers[11];
            4'd12: rt = registers[12];
            4'd13: rt = {{(DATA_BITS-8){1'b0}}, block_id};
            4'd14: rt = {{(DATA_BITS-8){1'b0}}, THREADS_PER_BLOCK[7:0]};
            4'd15: rt = {{(DATA_BITS-8){1'b0}}, THREAD_ID[7:0]};
            default: rt = {DATA_BITS{1'b0}};
        endcase
    end

    always @(*) begin
        case (decoded_rd_address)
            4'd0:  rd_data = registers[0];
            4'd1:  rd_data = registers[1];
            4'd2:  rd_data = registers[2];
            4'd3:  rd_data = registers[3];
            4'd4:  rd_data = registers[4];
            4'd5:  rd_data = registers[5];
            4'd6:  rd_data = registers[6];
            4'd7:  rd_data = registers[7];
            4'd8:  rd_data = registers[8];
            4'd9:  rd_data = registers[9];
            4'd10: rd_data = registers[10];
            4'd11: rd_data = registers[11];
            4'd12: rd_data = registers[12];
            4'd13: rd_data = {{(DATA_BITS-8){1'b0}}, block_id};
            4'd14: rd_data = {{(DATA_BITS-8){1'b0}}, THREADS_PER_BLOCK[7:0]};
            4'd15: rd_data = {{(DATA_BITS-8){1'b0}}, THREAD_ID[7:0]};
            default: rd_data = {DATA_BITS{1'b0}};
        endcase
    end

    // Sign-extend 8-bit immediate to 16-bit
    wire [DATA_BITS-1:0] immediate_extended;
    assign immediate_extended = {{8{decoded_immediate[7]}}, decoded_immediate};

    // Pre-multiplex the write data to avoid generating separate multi-input muxes for each register.
    reg [DATA_BITS-1:0] write_data;
    always @(*) begin
        case (decoded_reg_input_mux)
            MUX_ALU:      write_data = alu_out;
            MUX_MEMORY:   write_data = lsu_out;
            MUX_CONSTANT: write_data = immediate_extended;
            MUX_FMA:      write_data = fma_out;
            MUX_ACT:      write_data = act_out;
            MUX_SYSTOLIC: write_data = systolic_out;
            default:      write_data = alu_out;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
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
            // registers[13], [14], and [15] are read-only and bypassed combinationally
        end else if (enable) begin 

            // Store rd when core_state = UPDATE
            if (core_state == 3'b110) begin 
                // Only allow writing to R0 - R12
                if (decoded_reg_write_enable && write_rd_address < 13) begin
                    registers[write_rd_address] <= write_data;
                end
            end
        end
    end
endmodule
