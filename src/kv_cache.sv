`default_nettype none
`timescale 1ns/1ns

// KV-CACHE FOR ATTENTION MECHANISM
// > Stores Key and Value tensors for transformer attention
// > Supports incremental decoding (append new KV pairs)
// > Circular buffer implementation for sliding window attention
// > Multi-head support with parallel access
module kv_cache #(
    parameter DATA_BITS = 16,             // SF16 fixed-point
    parameter NUM_HEADS = 4,              // Number of attention heads
    parameter HEAD_DIM = 16,              // Dimension per head
    parameter MAX_SEQ_LEN = 256           // Maximum sequence length
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Cache control
    input wire clear_cache,               // Reset cache state
    input wire append_mode,               // Append new KV (incremental decode)
    
    // Current sequence position
    input wire [$clog2(MAX_SEQ_LEN)-1:0] seq_position,
    output reg [$clog2(MAX_SEQ_LEN)-1:0] cache_length,  // Current cached length

    // Key write interface (for caching new keys)
    input wire key_write_en,
    input wire [$clog2(NUM_HEADS)-1:0] key_head_sel,
    input wire [$clog2(HEAD_DIM)-1:0] key_dim_sel,
    input wire [DATA_BITS-1:0] key_data_in,

    // Value write interface (for caching new values)
    input wire value_write_en,
    input wire [$clog2(NUM_HEADS)-1:0] value_head_sel,
    input wire [$clog2(HEAD_DIM)-1:0] value_dim_sel,
    input wire [DATA_BITS-1:0] value_data_in,

    // Key read interface (for attention computation)
    input wire key_read_en,
    input wire [$clog2(NUM_HEADS)-1:0] key_read_head,
    input wire [$clog2(MAX_SEQ_LEN)-1:0] key_read_pos,
    input wire [$clog2(HEAD_DIM)-1:0] key_read_dim,
    output reg [DATA_BITS-1:0] key_data_out,
    output reg key_valid,

    // Value read interface (for attention computation)
    input wire value_read_en,
    input wire [$clog2(NUM_HEADS)-1:0] value_read_head,
    input wire [$clog2(MAX_SEQ_LEN)-1:0] value_read_pos,
    input wire [$clog2(HEAD_DIM)-1:0] value_read_dim,
    output reg [DATA_BITS-1:0] value_data_out,
    output reg value_valid,

    // Batch read for attention (read entire head's keys for one position)
    input wire batch_read_en,
    input wire [$clog2(NUM_HEADS)-1:0] batch_head_sel,
    input wire [$clog2(MAX_SEQ_LEN)-1:0] batch_start_pos,
    input wire [$clog2(MAX_SEQ_LEN)-1:0] batch_end_pos,
    output reg batch_valid,
    output reg batch_done,

    // Sliding window control
    input wire sliding_window_en,
    input wire [$clog2(MAX_SEQ_LEN)-1:0] window_size,

    // Status
    output reg cache_full,
    output reg [$clog2(MAX_SEQ_LEN)-1:0] oldest_position
);
    // Cache storage
    // Organized as: [head][position][dimension]
    // For simplicity, we flatten to 2D arrays per head
    
    // Key cache - one memory per head
    reg [DATA_BITS-1:0] key_cache_h0 [MAX_SEQ_LEN*HEAD_DIM-1:0];
    reg [DATA_BITS-1:0] key_cache_h1 [MAX_SEQ_LEN*HEAD_DIM-1:0];
    reg [DATA_BITS-1:0] key_cache_h2 [MAX_SEQ_LEN*HEAD_DIM-1:0];
    reg [DATA_BITS-1:0] key_cache_h3 [MAX_SEQ_LEN*HEAD_DIM-1:0];

    // Value cache - one memory per head
    reg [DATA_BITS-1:0] value_cache_h0 [MAX_SEQ_LEN*HEAD_DIM-1:0];
    reg [DATA_BITS-1:0] value_cache_h1 [MAX_SEQ_LEN*HEAD_DIM-1:0];
    reg [DATA_BITS-1:0] value_cache_h2 [MAX_SEQ_LEN*HEAD_DIM-1:0];
    reg [DATA_BITS-1:0] value_cache_h3 [MAX_SEQ_LEN*HEAD_DIM-1:0];

    // Circular buffer pointers
    reg [$clog2(MAX_SEQ_LEN)-1:0] window_start;

    // Address calculation
    localparam ADDR_WIDTH = $clog2(MAX_SEQ_LEN*HEAD_DIM);
    wire [ADDR_WIDTH-1:0] key_write_addr = ADDR_WIDTH'(seq_position) * ADDR_WIDTH'(HEAD_DIM) + ADDR_WIDTH'(key_dim_sel);
    wire [ADDR_WIDTH-1:0] value_write_addr = ADDR_WIDTH'(seq_position) * ADDR_WIDTH'(HEAD_DIM) + ADDR_WIDTH'(value_dim_sel);
    wire [ADDR_WIDTH-1:0] key_read_addr = ADDR_WIDTH'(key_read_pos) * ADDR_WIDTH'(HEAD_DIM) + ADDR_WIDTH'(key_read_dim);
    wire [ADDR_WIDTH-1:0] value_read_addr = ADDR_WIDTH'(value_read_pos) * ADDR_WIDTH'(HEAD_DIM) + ADDR_WIDTH'(value_read_dim);

    // Batch read state
    reg [$clog2(MAX_SEQ_LEN)-1:0] batch_counter;
    reg batch_in_progress;

    // Read data selection
    reg [DATA_BITS-1:0] key_read_data;
    reg [DATA_BITS-1:0] value_read_data;

    // Key read mux
    always @(*) begin
        key_read_data = {DATA_BITS{1'b0}};
        case (key_read_head)
            2'd0: key_read_data = key_cache_h0[key_read_addr];
            2'd1: key_read_data = key_cache_h1[key_read_addr];
            2'd2: key_read_data = key_cache_h2[key_read_addr];
            2'd3: key_read_data = key_cache_h3[key_read_addr];
        endcase
    end

    // Value read mux
    always @(*) begin
        value_read_data = {DATA_BITS{1'b0}};
        case (value_read_head)
            2'd0: value_read_data = value_cache_h0[value_read_addr];
            2'd1: value_read_data = value_cache_h1[value_read_addr];
            2'd2: value_read_data = value_cache_h2[value_read_addr];
            2'd3: value_read_data = value_cache_h3[value_read_addr];
        endcase
    end

    always @(posedge clk) begin
        if (reset || clear_cache) begin
            cache_length <= 0;
            window_start <= 0;
            oldest_position <= 0;
            cache_full <= 1'b0;
            key_data_out <= {DATA_BITS{1'b0}};
            key_valid <= 1'b0;
            value_data_out <= {DATA_BITS{1'b0}};
            value_valid <= 1'b0;
            batch_valid <= 1'b0;
            batch_done <= 1'b0;
            batch_counter <= 0;
            batch_in_progress <= 1'b0;
        end
        else if (enable) begin
            // Default outputs
            key_valid <= 1'b0;
            value_valid <= 1'b0;
            batch_done <= 1'b0;

            // Key write
            if (key_write_en) begin
                case (key_head_sel)
                    2'd0: key_cache_h0[key_write_addr] <= key_data_in;
                    2'd1: key_cache_h1[key_write_addr] <= key_data_in;
                    2'd2: key_cache_h2[key_write_addr] <= key_data_in;
                    2'd3: key_cache_h3[key_write_addr] <= key_data_in;
                endcase
            end

            // Value write
            if (value_write_en) begin
                case (value_head_sel)
                    2'd0: value_cache_h0[value_write_addr] <= value_data_in;
                    2'd1: value_cache_h1[value_write_addr] <= value_data_in;
                    2'd2: value_cache_h2[value_write_addr] <= value_data_in;
                    2'd3: value_cache_h3[value_write_addr] <= value_data_in;
                endcase
                
                // Update cache length in append mode
                if (append_mode && 32'(value_dim_sel) == 32'(HEAD_DIM - 1)) begin
                    if (32'(cache_length) < 32'(MAX_SEQ_LEN)) begin
                        cache_length <= cache_length + 1;
                    end else begin
                        cache_full <= 1'b1;
                        // Sliding window: advance window start
                        if (sliding_window_en) begin
                            window_start <= window_start + 1;
                            oldest_position <= oldest_position + 1;
                        end
                    end
                end
            end

            // Key read
            if (key_read_en) begin
                key_data_out <= key_read_data;
                key_valid <= 1'b1;
            end

            // Value read
            if (value_read_en) begin
                value_data_out <= value_read_data;
                value_valid <= 1'b1;
            end

            // Batch read handling
            if (batch_read_en && !batch_in_progress) begin
                batch_in_progress <= 1'b1;
                batch_counter <= batch_start_pos;
                batch_valid <= 1'b0;
            end

            if (batch_in_progress) begin
                batch_counter <= batch_counter + 1;
                batch_valid <= 1'b1;
                
                if (batch_counter >= batch_end_pos) begin
                    batch_in_progress <= 1'b0;
                    batch_done <= 1'b1;
                    batch_valid <= 1'b0;
                end
            end
        end
    end

endmodule

