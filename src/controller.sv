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

    // Consumer Interface (Fetchers / LSUs) - Flattened for synthesis
    input wire [NUM_CONSUMERS-1:0] consumer_read_valid,
    input wire [ADDR_BITS*NUM_CONSUMERS-1:0] consumer_read_address_flat,
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready,
    output wire [DATA_BITS*NUM_CONSUMERS-1:0] consumer_read_data_flat,
    input wire [NUM_CONSUMERS-1:0] consumer_write_valid,
    input wire [ADDR_BITS*NUM_CONSUMERS-1:0] consumer_write_address_flat,
    input wire [DATA_BITS*NUM_CONSUMERS-1:0] consumer_write_data_flat,
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready,

    // Memory Interface (Data / Program) - Flattened for synthesis
    output reg [NUM_CHANNELS-1:0] mem_read_valid,
    output wire [ADDR_BITS*NUM_CHANNELS-1:0] mem_read_address_flat,
    input wire [NUM_CHANNELS-1:0] mem_read_ready,
    input wire [DATA_BITS*NUM_CHANNELS-1:0] mem_read_data_flat,
    output reg [NUM_CHANNELS-1:0] mem_write_valid,
    output wire [ADDR_BITS*NUM_CHANNELS-1:0] mem_write_address_flat,
    output wire [DATA_BITS*NUM_CHANNELS-1:0] mem_write_data_flat,
    input wire [NUM_CHANNELS-1:0] mem_write_ready
);
    // Unflatten interfaces for internal use
    wire [ADDR_BITS-1:0] consumer_read_address [NUM_CONSUMERS-1:0];
    reg [DATA_BITS-1:0] consumer_read_data [NUM_CONSUMERS-1:0];
    wire [ADDR_BITS-1:0] consumer_write_address [NUM_CONSUMERS-1:0];
    wire [DATA_BITS-1:0] consumer_write_data [NUM_CONSUMERS-1:0];
    reg [ADDR_BITS-1:0] mem_read_address [NUM_CHANNELS-1:0];
    wire [DATA_BITS-1:0] mem_read_data [NUM_CHANNELS-1:0];
    reg [ADDR_BITS-1:0] mem_write_address [NUM_CHANNELS-1:0];
    reg [DATA_BITS-1:0] mem_write_data [NUM_CHANNELS-1:0];

    // Unflatten consumer inputs
    genvar c;
    generate
        for (c = 0; c < NUM_CONSUMERS; c = c + 1) begin : unflatten_consumer
            assign consumer_read_address[c] = consumer_read_address_flat[(c+1)*ADDR_BITS-1 : c*ADDR_BITS];
            assign consumer_write_address[c] = consumer_write_address_flat[(c+1)*ADDR_BITS-1 : c*ADDR_BITS];
            assign consumer_write_data[c] = consumer_write_data_flat[(c+1)*DATA_BITS-1 : c*DATA_BITS];
        end
    endgenerate

    // Unflatten memory inputs
    genvar m;
    generate
        for (m = 0; m < NUM_CHANNELS; m = m + 1) begin : unflatten_mem
            assign mem_read_data[m] = mem_read_data_flat[(m+1)*DATA_BITS-1 : m*DATA_BITS];
        end
    endgenerate

    // Flatten outputs - done using generate to directly connect internal arrays to flat output ports
    genvar f;
    generate
        for (f = 0; f < NUM_CONSUMERS; f = f + 1) begin : flatten_consumer_outputs
            assign consumer_read_data_flat[(f+1)*DATA_BITS-1 : f*DATA_BITS] = consumer_read_data[f];
        end
        for (f = 0; f < NUM_CHANNELS; f = f + 1) begin : flatten_mem_outputs
            assign mem_read_address_flat[(f+1)*ADDR_BITS-1 : f*ADDR_BITS] = mem_read_address[f];
            assign mem_write_address_flat[(f+1)*ADDR_BITS-1 : f*ADDR_BITS] = mem_write_address[f];
            assign mem_write_data_flat[(f+1)*DATA_BITS-1 : f*DATA_BITS] = mem_write_data[f];
        end
    endgenerate

    localparam IDLE = 3'b000, 
        READ_WAITING = 3'b010, 
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;

    // Keep track of state for each channel and which jobs each channel is handling
    localparam SEL_WIDTH = ($clog2(NUM_CONSUMERS) > 0) ? $clog2(NUM_CONSUMERS) : 1;
    reg [2:0] controller_state [NUM_CHANNELS-1:0];
    reg [SEL_WIDTH-1:0] current_consumer [NUM_CHANNELS-1:0]; // Which consumer is each channel currently serving
    reg [NUM_CONSUMERS-1:0] channel_serving_consumer; // Which channels are being served? Prevents many workers from picking up the same request.

    // Arbitration temporaries (computed each clock)
    reg [NUM_CONSUMERS-1:0] serving_next;
    integer sel;
    reg sel_is_write;

    integer i, j, k;
    
    always @(posedge clk) begin
        if (reset) begin 
            mem_read_valid <= {NUM_CHANNELS{1'b0}};
            mem_write_valid <= {NUM_CHANNELS{1'b0}};
            consumer_read_ready <= {NUM_CONSUMERS{1'b0}};
            consumer_write_ready <= {NUM_CONSUMERS{1'b0}};
            channel_serving_consumer <= 0;
            serving_next = {NUM_CONSUMERS{1'b0}};

            for (k = 0; k < NUM_CHANNELS; k = k + 1) begin
                mem_read_address[k] <= {ADDR_BITS{1'b0}};
                mem_write_address[k] <= {ADDR_BITS{1'b0}};
                mem_write_data[k] <= {DATA_BITS{1'b0}};
            end
            for (k = 0; k < NUM_CONSUMERS; k = k + 1) begin
                consumer_read_data[k] <= {DATA_BITS{1'b0}};
            end
            
            for (k = 0; k < NUM_CHANNELS; k = k + 1) begin
                controller_state[k] <= IDLE;
                current_consumer[k] <= {SEL_WIDTH{1'b0}};
            end
        end else begin 
            // Next-state for the cross-channel arbitration mask. Use blocking assignments so
            // channel i+1 sees the selection made by channel i in the same clock edge.
            serving_next = channel_serving_consumer;

            // For each channel, we handle processing concurrently
            for (i = 0; i < NUM_CHANNELS; i = i + 1) begin 
                case (controller_state[i])
                    IDLE: begin
                        // Pick exactly one consumer for this channel (priority: lowest index).
                        sel = -1;
                        sel_is_write = 1'b0;

                        for (j = 0; j < NUM_CONSUMERS; j = j + 1) begin 
                            if (sel == -1) begin
                                if (consumer_read_valid[j] && !serving_next[j]) begin
                                    sel = j;
                                    sel_is_write = 1'b0;
                                end else if (WRITE_ENABLE && consumer_write_valid[j] && !serving_next[j]) begin
                                    sel = j;
                                    sel_is_write = 1'b1;
                                end
                            end
                        end

                        if (sel != -1) begin
                            serving_next[sel] = 1'b1;
                            current_consumer[i] <= SEL_WIDTH'(sel);

                            if (!sel_is_write) begin
                                mem_read_valid[i] <= 1'b1;
                                mem_read_address[i] <= consumer_read_address[sel];
                                controller_state[i] <= READ_WAITING;
                            end else begin
                                mem_write_valid[i] <= 1'b1;
                                mem_write_address[i] <= consumer_write_address[sel];
                                mem_write_data[i] <= consumer_write_data[sel];
                                controller_state[i] <= WRITE_WAITING;
                            end
                        end
                    end
                    READ_WAITING: begin
                        // Wait for response from memory for pending read request
                        if (mem_read_ready[i]) begin 
                            mem_read_valid[i] <= 0;
                            consumer_read_ready[current_consumer[i]] <= 1;
                            consumer_read_data[current_consumer[i]] <= mem_read_data[i];
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
                            serving_next[current_consumer[i]] = 1'b0;
                            consumer_read_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                    WRITE_RELAYING: begin 
                        if (!consumer_write_valid[current_consumer[i]]) begin 
                            serving_next[current_consumer[i]] = 1'b0;
                            consumer_write_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                    default: begin
                        controller_state[i] <= IDLE;
                    end
                endcase
            end

            channel_serving_consumer <= serving_next;

            channel_serving_consumer <= serving_next;
        end
    end
endmodule
