`default_nettype none
`timescale 1ns/1ns

// DEDICATED WEIGHT AND ACTIVATION MEMORY BANKS
// > Separate memory banks for weights and activations
// > Enables parallel access during matrix operations
// > Double-buffering support for prefetching
// > Optimized for neural network inference
module weight_mem #(
    parameter DATA_BITS = 16,
    parameter ADDR_BITS = 12,             // 4K entries per bank
    parameter NUM_BANKS = 4,              // Number of parallel banks
    parameter BANK_DEPTH = 1024           // Entries per bank
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Weight bank interface (read-only during inference)
    input wire weight_read_en,
    input wire [$clog2(NUM_BANKS)-1:0] weight_bank_sel,
    input wire [$clog2(BANK_DEPTH)-1:0] weight_addr,
    output reg [DATA_BITS-1:0] weight_data_out,
    output reg weight_valid,

    // Weight loading interface (for initialization)
    input wire weight_write_en,
    input wire [$clog2(NUM_BANKS)-1:0] weight_write_bank,
    input wire [$clog2(BANK_DEPTH)-1:0] weight_write_addr,
    input wire [DATA_BITS-1:0] weight_write_data,

    // Activation bank interface (read/write)
    input wire act_read_en,
    input wire act_write_en,
    input wire [$clog2(NUM_BANKS)-1:0] act_bank_sel,
    input wire [$clog2(BANK_DEPTH)-1:0] act_addr,
    input wire [DATA_BITS-1:0] act_data_in,
    output reg [DATA_BITS-1:0] act_data_out,
    output reg act_valid,

    // Double buffer control
    input wire buffer_select,              // 0 or 1 for double buffering
    input wire swap_buffers,               // Trigger buffer swap

    // Prefetch interface
    input wire prefetch_en,
    input wire [$clog2(BANK_DEPTH)-1:0] prefetch_start_addr,
    input wire [$clog2(BANK_DEPTH)-1:0] prefetch_length,
    output reg prefetch_done,

    // Status
    output reg [NUM_BANKS-1:0] bank_busy
);
    // Weight memory banks (2 buffers for double buffering)
    reg [DATA_BITS-1:0] weight_bank_0_buf0 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] weight_bank_0_buf1 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] weight_bank_1_buf0 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] weight_bank_1_buf1 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] weight_bank_2_buf0 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] weight_bank_2_buf1 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] weight_bank_3_buf0 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] weight_bank_3_buf1 [BANK_DEPTH-1:0];

    // Activation memory banks (2 buffers)
    reg [DATA_BITS-1:0] act_bank_0_buf0 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] act_bank_0_buf1 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] act_bank_1_buf0 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] act_bank_1_buf1 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] act_bank_2_buf0 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] act_bank_2_buf1 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] act_bank_3_buf0 [BANK_DEPTH-1:0];
    reg [DATA_BITS-1:0] act_bank_3_buf1 [BANK_DEPTH-1:0];

    // Buffer selection
    reg active_buffer;  // Which buffer is currently active

    // Prefetch state
    reg prefetching;
    reg [$clog2(BANK_DEPTH)-1:0] prefetch_counter;
    reg [$clog2(BANK_DEPTH)-1:0] prefetch_end;

    // Read data selection
    reg [DATA_BITS-1:0] weight_read_data;
    reg [DATA_BITS-1:0] act_read_data;

    // Weight read logic
    always @(*) begin
        weight_read_data = {DATA_BITS{1'b0}};
        if (weight_read_en) begin
            case (weight_bank_sel)
                2'd0: weight_read_data = active_buffer ? weight_bank_0_buf1[weight_addr] : weight_bank_0_buf0[weight_addr];
                2'd1: weight_read_data = active_buffer ? weight_bank_1_buf1[weight_addr] : weight_bank_1_buf0[weight_addr];
                2'd2: weight_read_data = active_buffer ? weight_bank_2_buf1[weight_addr] : weight_bank_2_buf0[weight_addr];
                2'd3: weight_read_data = active_buffer ? weight_bank_3_buf1[weight_addr] : weight_bank_3_buf0[weight_addr];
            endcase
        end
    end

    // Activation read logic
    always @(*) begin
        act_read_data = {DATA_BITS{1'b0}};
        if (act_read_en) begin
            case (act_bank_sel)
                2'd0: act_read_data = active_buffer ? act_bank_0_buf1[act_addr] : act_bank_0_buf0[act_addr];
                2'd1: act_read_data = active_buffer ? act_bank_1_buf1[act_addr] : act_bank_1_buf0[act_addr];
                2'd2: act_read_data = active_buffer ? act_bank_2_buf1[act_addr] : act_bank_2_buf0[act_addr];
                2'd3: act_read_data = active_buffer ? act_bank_3_buf1[act_addr] : act_bank_3_buf0[act_addr];
            endcase
        end
    end

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            weight_data_out <= {DATA_BITS{1'b0}};
            weight_valid <= 1'b0;
            act_data_out <= {DATA_BITS{1'b0}};
            act_valid <= 1'b0;
            active_buffer <= 1'b0;
            prefetching <= 1'b0;
            prefetch_done <= 1'b0;
            prefetch_counter <= 0;
            prefetch_end <= 0;
            bank_busy <= {NUM_BANKS{1'b0}};
        end
        else if (enable) begin
            // Default outputs
            weight_valid <= 1'b0;
            act_valid <= 1'b0;
            prefetch_done <= 1'b0;

            // Buffer swap
            if (swap_buffers) begin
                active_buffer <= ~active_buffer;
            end

            // Weight read (1-cycle latency)
            if (weight_read_en) begin
                weight_data_out <= weight_read_data;
                weight_valid <= 1'b1;
            end

            // Weight write (to inactive buffer for double buffering)
            if (weight_write_en) begin
                case (weight_write_bank)
                    2'd0: begin
                        if (active_buffer)
                            weight_bank_0_buf0[weight_write_addr] <= weight_write_data;
                        else
                            weight_bank_0_buf1[weight_write_addr] <= weight_write_data;
                    end
                    2'd1: begin
                        if (active_buffer)
                            weight_bank_1_buf0[weight_write_addr] <= weight_write_data;
                        else
                            weight_bank_1_buf1[weight_write_addr] <= weight_write_data;
                    end
                    2'd2: begin
                        if (active_buffer)
                            weight_bank_2_buf0[weight_write_addr] <= weight_write_data;
                        else
                            weight_bank_2_buf1[weight_write_addr] <= weight_write_data;
                    end
                    2'd3: begin
                        if (active_buffer)
                            weight_bank_3_buf0[weight_write_addr] <= weight_write_data;
                        else
                            weight_bank_3_buf1[weight_write_addr] <= weight_write_data;
                    end
                endcase
            end

            // Activation read (1-cycle latency)
            if (act_read_en) begin
                act_data_out <= act_read_data;
                act_valid <= 1'b1;
            end

            // Activation write
            if (act_write_en) begin
                case (act_bank_sel)
                    2'd0: begin
                        if (active_buffer)
                            act_bank_0_buf1[act_addr] <= act_data_in;
                        else
                            act_bank_0_buf0[act_addr] <= act_data_in;
                    end
                    2'd1: begin
                        if (active_buffer)
                            act_bank_1_buf1[act_addr] <= act_data_in;
                        else
                            act_bank_1_buf0[act_addr] <= act_data_in;
                    end
                    2'd2: begin
                        if (active_buffer)
                            act_bank_2_buf1[act_addr] <= act_data_in;
                        else
                            act_bank_2_buf0[act_addr] <= act_data_in;
                    end
                    2'd3: begin
                        if (active_buffer)
                            act_bank_3_buf1[act_addr] <= act_data_in;
                        else
                            act_bank_3_buf0[act_addr] <= act_data_in;
                    end
                endcase
            end

            // Prefetch handling
            if (prefetch_en && !prefetching) begin
                prefetching <= 1'b1;
                prefetch_counter <= prefetch_start_addr;
                prefetch_end <= prefetch_start_addr + prefetch_length;
                bank_busy <= {NUM_BANKS{1'b1}};
            end
            
            if (prefetching) begin
                prefetch_counter <= prefetch_counter + 1;
                if (prefetch_counter >= prefetch_end - 1) begin
                    prefetching <= 1'b0;
                    prefetch_done <= 1'b1;
                    bank_busy <= {NUM_BANKS{1'b0}};
                end
            end
        end
    end
endmodule

