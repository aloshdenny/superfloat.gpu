`default_nettype none
`timescale 1ns/1ns

// LOAD-STORE UNIT (Q1.15 Fixed-Point)
// > Handles asynchronous memory load and store operations and waits for response
// > Each thread in each core has its own LSU
// > LDR, STR instructions are executed here
// > Supports 16-bit Q1.15 data transfers
module lsu #(
    parameter ADDR_BITS = 8,   // Address width (8-bit for 256 memory locations)
    parameter DATA_BITS = 16  // Data width (16-bit for Q1.15 fixed-point)
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads than block size, some LSUs will be inactive

    // State
    input reg [2:0] core_state,

    // Memory Control Signals
    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,

    // Registers (16-bit Q1.15)
    // For LDR: rs contains the memory address (lower 8 bits used)
    // For STR: rs contains the memory address, rt contains the data to store
    input reg [DATA_BITS-1:0] rs,
    input reg [DATA_BITS-1:0] rt,

    // Data Memory Interface
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input reg mem_read_ready,
    input reg [DATA_BITS-1:0] mem_read_data,
    output reg mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address,
    output reg [DATA_BITS-1:0] mem_write_data,
    input reg mem_write_ready,

    // LSU Outputs
    output reg [1:0] lsu_state,
    output reg [DATA_BITS-1:0] lsu_out
);
    localparam IDLE = 2'b00, REQUESTING = 2'b01, WAITING = 2'b10, DONE = 2'b11;

    always @(posedge clk) begin
        if (reset) begin
            lsu_state <= IDLE;
            lsu_out <= {DATA_BITS{1'b0}};
            mem_read_valid <= 0;
            mem_read_address <= {ADDR_BITS{1'b0}};
            mem_write_valid <= 0;
            mem_write_address <= {ADDR_BITS{1'b0}};
            mem_write_data <= {DATA_BITS{1'b0}};
        end else if (enable) begin
            // If memory read enable is triggered (LDR instruction)
            if (decoded_mem_read_enable) begin 
                case (lsu_state)
                    IDLE: begin
                        // Only read when core_state = REQUEST
                        if (core_state == 3'b011) begin 
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin 
                        mem_read_valid <= 1;
                        // Use lower bits of rs as memory address
                        mem_read_address <= rs[ADDR_BITS-1:0];
                        lsu_state <= WAITING;
                    end
                    WAITING: begin
                        if (mem_read_ready == 1) begin
                            mem_read_valid <= 0;
                            // Load 16-bit Q1.15 value from memory
                            lsu_out <= mem_read_data;
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin 
                        // Reset when core_state = UPDATE
                        if (core_state == 3'b110) begin 
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end

            // If memory write enable is triggered (STR instruction)
            if (decoded_mem_write_enable) begin 
                case (lsu_state)
                    IDLE: begin
                        // Only write when core_state = REQUEST
                        if (core_state == 3'b011) begin 
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin 
                        mem_write_valid <= 1;
                        // Use lower bits of rs as memory address
                        mem_write_address <= rs[ADDR_BITS-1:0];
                        // Store full 16-bit Q1.15 value
                        mem_write_data <= rt;
                        lsu_state <= WAITING;
                    end
                    WAITING: begin
                        if (mem_write_ready) begin
                            mem_write_valid <= 0;
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin 
                        // Reset when core_state = UPDATE
                        if (core_state == 3'b110) begin 
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
