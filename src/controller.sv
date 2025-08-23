`default_nettype none
`timescale 1ns/1ns

// MEMORY CONTROLLER
// > Receives memory requests from all cores
// > Throttles requests based on limited external memory bandwidth
// > Waits for responses from external memory and distributes them back to cores
module controller #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter NUM_CONSUMERS = 4, // The number of consumers accessing memory through this controller
    parameter NUM_CHANNELS = 1,  // The number of concurrent channels available to send requests to global memory
    parameter WRITE_ENABLE = 1   // Whether this memory controller can write to memory (program memory is read-only)
) (
    input wire clk,
    input wire reset,

    // Consumer Interface (Fetchers / LSUs) - Flattened arrays for Verilog-2005 compatibility
    input wire [NUM_CONSUMERS-1:0] consumer_read_valid,
    input wire [NUM_CONSUMERS*ADDR_BITS-1:0] consumer_read_address,
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready,
    output reg [NUM_CONSUMERS*DATA_BITS-1:0] consumer_read_data,
    input wire [NUM_CONSUMERS-1:0] consumer_write_valid,
    input wire [NUM_CONSUMERS*ADDR_BITS-1:0] consumer_write_address,
    input wire [NUM_CONSUMERS*DATA_BITS-1:0] consumer_write_data,
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready,

    // Memory Interface (Data / Program) - Flattened arrays for Verilog-2005 compatibility
    output reg [NUM_CHANNELS-1:0] mem_read_valid,
    output reg [NUM_CHANNELS*ADDR_BITS-1:0] mem_read_address,
    input wire [NUM_CHANNELS-1:0] mem_read_ready,
    input wire [NUM_CHANNELS*DATA_BITS-1:0] mem_read_data,
    output reg [NUM_CHANNELS-1:0] mem_write_valid,
    output reg [NUM_CHANNELS*ADDR_BITS-1:0] mem_write_address,
    output reg [NUM_CHANNELS*DATA_BITS-1:0] mem_write_data,
    input wire [NUM_CHANNELS-1:0] mem_write_ready
);
    localparam IDLE = 3'b000, 
        READ_WAITING = 3'b010, 
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;

    // Keep track of state for each channel and which jobs each channel is handling
    reg [2:0] controller_state [NUM_CHANNELS-1:0];
    reg [$clog2(NUM_CONSUMERS)-1:0] current_consumer [NUM_CHANNELS-1:0]; // Which consumer is each channel currently serving
    reg [NUM_CONSUMERS-1:0] channel_serving_consumer; // Which channels are being served? Prevents many workers from picking up the same request.

    integer i, j, k;
    
    always @(posedge clk) begin
        if (reset) begin 
            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;
            consumer_read_ready <= 0;
            consumer_read_data <= 0;
            consumer_write_ready <= 0;
            channel_serving_consumer <= 0;
            
            for (k = 0; k < NUM_CHANNELS; k = k + 1) begin
                controller_state[k] <= IDLE;
                current_consumer[k] <= 0;
            end
        end else begin 
            // For each channel, we handle processing concurrently
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin 
                case (controller_state[i])
                    IDLE: begin
                        // While this channel is idle, cycle through consumers looking for one with a pending request
                        for (j = 0; j < NUM_CONSUMERS; j = j + 1) begin 
                            if (consumer_read_valid[j] && !channel_serving_consumer[j]) begin 
                                channel_serving_consumer[j] <= 1;
                                current_consumer[i] <= j;

                                mem_read_valid[i] <= 1;
                                mem_read_address[i*ADDR_BITS +: ADDR_BITS] <= consumer_read_address[j*ADDR_BITS +: ADDR_BITS];
                                controller_state[i] <= READ_WAITING;
                            end else if (consumer_write_valid[j] && !channel_serving_consumer[j]) begin 
                                channel_serving_consumer[j] <= 1;
                                current_consumer[i] <= j;

                                mem_write_valid[i] <= 1;
                                mem_write_address[i*ADDR_BITS +: ADDR_BITS] <= consumer_write_address[j*ADDR_BITS +: ADDR_BITS];
                                mem_write_data[i*DATA_BITS +: DATA_BITS] <= consumer_write_data[j*DATA_BITS +: DATA_BITS];
                                controller_state[i] <= WRITE_WAITING;
                            end
                        end
                    end
                    READ_WAITING: begin
                        // Wait for response from memory for pending read request
                        if (mem_read_ready[i]) begin 
                            mem_read_valid[i] <= 0;
                            consumer_read_ready[current_consumer[i]] <= 1;
                            consumer_read_data[current_consumer[i]*DATA_BITS +: DATA_BITS] <= mem_read_data[i*DATA_BITS +: DATA_BITS];
                            controller_state[i] <= READ_RELAYING;
                        end
                    end
                    WRITE_WAITING: begin 
                        // Wait for response from memory for pending write request
                        if (mem_write_ready[i]) begin 
                            mem_write_valid[i] <= 0;
                            consumer_write_ready[current_consumer[i]] <= 1;
                            controller_state[i] <= WRITE_RELAYING;
                        end
                    end
                    // Wait until consumer acknowledges it received response, then reset
                    READ_RELAYING: begin
                        if (!consumer_read_valid[current_consumer[i]]) begin 
                            channel_serving_consumer[current_consumer[i]] <= 0;
                            consumer_read_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                    WRITE_RELAYING: begin 
                        if (!consumer_write_valid[current_consumer[i]]) begin 
                            channel_serving_consumer[current_consumer[i]] <= 0;
                            consumer_write_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
