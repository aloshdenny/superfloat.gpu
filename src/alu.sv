`default_nettype none
`timescale 1ns/1ns

// ARITHMETIC-LOGIC UNIT (Integer Operations)
// > Executes integer computations for indexing and addressing
// > Each thread in each core has its own ALU
// > ADD, SUB, MUL, DIV instructions for index calculations
// > Q1.15 matrix operations are handled by the FMA unit instead
module alu #(
    parameter DATA_BITS = 16  // 16-bit data width
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads than block size, some ALUs will be inactive

    input reg [2:0] core_state,

    input reg [1:0] decoded_alu_arithmetic_mux,
    input reg decoded_alu_output_mux,

    input reg [DATA_BITS-1:0] rs,
    input reg [DATA_BITS-1:0] rt,
    output wire [DATA_BITS-1:0] alu_out
);
    // Integer operation codes
    localparam ADD = 2'b00,
        SUB = 2'b01,
        MUL = 2'b10,
        DIV = 2'b11;

    reg [DATA_BITS-1:0] alu_out_reg;
    assign alu_out = alu_out_reg;

    always @(posedge clk) begin 
        if (reset) begin 
            alu_out_reg <= {DATA_BITS{1'b0}};
        end else if (enable) begin
            // Calculate alu_out when core_state = EXECUTE
            if (core_state == 3'b101) begin 
                if (decoded_alu_output_mux == 1) begin 
                    // CMP instruction: Set NZP flags based on comparison
                    // Compare as signed integers for proper handling
                    // Output ordering matches LC-3 style BR masks and the PC unit:
                    // bit[2]=N (rs < rt), bit[1]=Z (rs == rt), bit[0]=P (rs > rt)
                    alu_out_reg <= {{(DATA_BITS-3){1'b0}},
                                   ($signed(rs) < $signed(rt)),  // negative
                                   (rs == rt),                    // zero
                                   ($signed(rs) > $signed(rt))}; // positive
                end else begin 
                    // Execute the specified integer arithmetic instruction
                    case (decoded_alu_arithmetic_mux)
                        ADD: begin 
                            alu_out_reg <= rs + rt;
                        end
                        SUB: begin 
                            alu_out_reg <= rs - rt;
                        end
                        MUL: begin 
                            alu_out_reg <= rs * rt;
                        end
                        DIV: begin 
                            // Integer division for indexing (row = i / N)
                            alu_out_reg <= (rt != 0) ? (rs / rt) : {DATA_BITS{1'b0}};
                        end
                    endcase
                end
            end
        end
    end
endmodule
