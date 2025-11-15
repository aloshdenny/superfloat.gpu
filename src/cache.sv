`default_nettype none
`timescale 1ns/1ns

// SIMPLE INSTRUCTION CACHE
// > Direct-mapped cache for program memory
// > Reduces memory bandwidth for instruction fetches
// > Configurable cache size and line width
// > Single-cycle hit, multi-cycle miss
module cache #(
    parameter ADDR_BITS = 8,           // Address width
    parameter DATA_BITS = 16,          // Data width (instruction size)
    parameter CACHE_SIZE = 16,         // Number of cache lines
    parameter LINE_SIZE = 1            // Instructions per cache line
) (
    input wire clk,
    input wire reset,

    // CPU/Core interface
    input wire read_valid,
    input wire [ADDR_BITS-1:0] read_address,
    output reg read_ready,
    output reg [DATA_BITS-1:0] read_data,

    // Memory interface
    output reg mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data
);
    // Cache parameters
    localparam INDEX_BITS = $clog2(CACHE_SIZE);
    localparam TAG_BITS = ADDR_BITS - INDEX_BITS;

    // Cache state
    localparam IDLE = 2'b00;
    localparam CHECK = 2'b01;
    localparam FETCH = 2'b10;
    localparam UPDATE = 2'b11;

    reg [1:0] cache_state;

    // Cache storage
    reg [DATA_BITS-1:0] cache_data [CACHE_SIZE-1:0];
    reg [TAG_BITS-1:0] cache_tag [CACHE_SIZE-1:0];
    reg cache_valid [CACHE_SIZE-1:0];

    // Address decomposition
    wire [INDEX_BITS-1:0] addr_index = read_address[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0] addr_tag = read_address[ADDR_BITS-1:INDEX_BITS];

    // Cache hit detection
    wire tag_match = (cache_tag[addr_index] == addr_tag);
    wire cache_hit = cache_valid[addr_index] && tag_match;

    // Registered address for miss handling
    reg [ADDR_BITS-1:0] pending_address;
    reg [INDEX_BITS-1:0] pending_index;
    reg [TAG_BITS-1:0] pending_tag;

    // Statistics (optional, for debugging)
    reg [15:0] hit_count;
    reg [15:0] miss_count;

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            cache_state <= IDLE;
            read_ready <= 1'b0;
            read_data <= {DATA_BITS{1'b0}};
            mem_read_valid <= 1'b0;
            mem_read_address <= {ADDR_BITS{1'b0}};
            pending_address <= {ADDR_BITS{1'b0}};
            pending_index <= {INDEX_BITS{1'b0}};
            pending_tag <= {TAG_BITS{1'b0}};
            hit_count <= 16'b0;
            miss_count <= 16'b0;
            
            // Initialize cache as invalid
            for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                cache_valid[i] <= 1'b0;
                cache_tag[i] <= {TAG_BITS{1'b0}};
                cache_data[i] <= {DATA_BITS{1'b0}};
            end
        end else begin
            case (cache_state)
                IDLE: begin
                    read_ready <= 1'b0;
                    mem_read_valid <= 1'b0;
                    
                    if (read_valid) begin
                        cache_state <= CHECK;
                        pending_address <= read_address;
                        pending_index <= addr_index;
                        pending_tag <= addr_tag;
                    end
                end

                CHECK: begin
                    if (cache_hit) begin
                        // Cache hit: return data immediately
                        read_data <= cache_data[pending_index];
                        read_ready <= 1'b1;
                        cache_state <= IDLE;
                        hit_count <= hit_count + 1'b1;
                    end else begin
                        // Cache miss: fetch from memory
                        mem_read_valid <= 1'b1;
                        mem_read_address <= pending_address;
                        cache_state <= FETCH;
                        miss_count <= miss_count + 1'b1;
                    end
                end

                FETCH: begin
                    // Wait for memory response
                    if (mem_read_ready) begin
                        mem_read_valid <= 1'b0;
                        cache_state <= UPDATE;
                    end
                end

                UPDATE: begin
                    // Update cache and return data
                    cache_data[pending_index] <= mem_read_data;
                    cache_tag[pending_index] <= pending_tag;
                    cache_valid[pending_index] <= 1'b1;
                    
                    read_data <= mem_read_data;
                    read_ready <= 1'b1;
                    cache_state <= IDLE;
                end

                default: begin
                    cache_state <= IDLE;
                end
            endcase
        end
    end
endmodule

