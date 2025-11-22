`default_nettype none
`timescale 1ns/1ns

// MEMORY COALESCING UNIT
// > Combines multiple memory requests to sequential addresses into single transactions
// > Reduces memory bandwidth usage when threads access contiguous memory
// > Detects coalescing opportunities and merges requests
// > Supports both read and write coalescing
module mem_coalesce #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter NUM_REQUESTS = 4,           // Number of input request ports
    parameter COALESCE_WIDTH = 4          // Max requests to coalesce (power of 2)
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Input requests from LSUs
    input wire [NUM_REQUESTS-1:0] req_valid,
    input wire [ADDR_BITS-1:0] req_address [NUM_REQUESTS-1:0],
    input wire [NUM_REQUESTS-1:0] req_is_write,
    input wire [DATA_BITS-1:0] req_write_data [NUM_REQUESTS-1:0],
    output reg [NUM_REQUESTS-1:0] req_ready,
    output reg [DATA_BITS-1:0] req_read_data [NUM_REQUESTS-1:0],

    // Output to memory controller (coalesced)
    output reg coalesced_valid,
    output reg [ADDR_BITS-1:0] coalesced_base_addr,
    output reg coalesced_is_write,
    output reg [$clog2(COALESCE_WIDTH):0] coalesced_count,  // Number of coalesced accesses
    output reg [DATA_BITS*COALESCE_WIDTH-1:0] coalesced_write_data,
    input wire coalesced_ready,
    input wire [DATA_BITS*COALESCE_WIDTH-1:0] coalesced_read_data
);
    // State machine
    localparam IDLE = 3'b000;
    localparam ANALYZE = 3'b001;
    localparam COALESCE = 3'b010;
    localparam REQUEST = 3'b011;
    localparam WAIT = 3'b100;
    localparam DISTRIBUTE = 3'b101;

    reg [2:0] state;

    // Pending request tracking
    reg [NUM_REQUESTS-1:0] pending_mask;
    reg [ADDR_BITS-1:0] pending_addr [NUM_REQUESTS-1:0];
    reg pending_is_write [NUM_REQUESTS-1:0];
    reg [DATA_BITS-1:0] pending_data [NUM_REQUESTS-1:0];

    // Coalescing analysis
    reg [ADDR_BITS-1:0] base_address;
    reg [NUM_REQUESTS-1:0] coalesce_mask;  // Which requests can be coalesced
    reg [$clog2(COALESCE_WIDTH):0] num_coalesced;
    reg coalesce_is_write;

    // Address sorting/analysis
    wire [ADDR_BITS-1:0] min_addr;
    wire [NUM_REQUESTS-1:0] sequential_mask;

    // Find minimum address among valid requests
    integer j;
    reg [ADDR_BITS-1:0] temp_min;
    always @(*) begin
        temp_min = {ADDR_BITS{1'b1}};  // Max value
        for (j = 0; j < NUM_REQUESTS; j = j + 1) begin
            if (pending_mask[j] && pending_addr[j] < temp_min) begin
                temp_min = pending_addr[j];
            end
        end
    end
    assign min_addr = temp_min;

    // Check which addresses are sequential from base
    genvar g;
    generate
        for (g = 0; g < NUM_REQUESTS; g = g + 1) begin : seq_check
            // Address is coalescable if within COALESCE_WIDTH of base
            assign sequential_mask[g] = pending_mask[g] && 
                                        (pending_addr[g] >= base_address) &&
                                        (pending_addr[g] < base_address + COALESCE_WIDTH);
        end
    endgenerate

    // Count coalesced requests
    integer k;
    reg [$clog2(COALESCE_WIDTH):0] count_ones;
    always @(*) begin
        count_ones = 0;
        for (k = 0; k < NUM_REQUESTS; k = k + 1) begin
            if (coalesce_mask[k]) count_ones = count_ones + 1;
        end
    end

    // Response data distribution
    integer m;
    
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            pending_mask <= {NUM_REQUESTS{1'b0}};
            coalesce_mask <= {NUM_REQUESTS{1'b0}};
            req_ready <= {NUM_REQUESTS{1'b0}};
            coalesced_valid <= 1'b0;
            coalesced_base_addr <= {ADDR_BITS{1'b0}};
            coalesced_is_write <= 1'b0;
            coalesced_count <= 0;
            coalesced_write_data <= {(DATA_BITS*COALESCE_WIDTH){1'b0}};
            num_coalesced <= 0;
            base_address <= {ADDR_BITS{1'b0}};
            coalesce_is_write <= 1'b0;
            
            for (m = 0; m < NUM_REQUESTS; m = m + 1) begin
                pending_addr[m] <= {ADDR_BITS{1'b0}};
                pending_is_write[m] <= 1'b0;
                pending_data[m] <= {DATA_BITS{1'b0}};
                req_read_data[m] <= {DATA_BITS{1'b0}};
            end
        end else if (enable) begin
            case (state)
                IDLE: begin
                    req_ready <= {NUM_REQUESTS{1'b0}};
                    coalesced_valid <= 1'b0;
                    
                    // Capture new requests
                    if (|req_valid) begin
                        pending_mask <= req_valid;
                        for (m = 0; m < NUM_REQUESTS; m = m + 1) begin
                            if (req_valid[m]) begin
                                pending_addr[m] <= req_address[m];
                                pending_is_write[m] <= req_is_write[m];
                                pending_data[m] <= req_write_data[m];
                            end
                        end
                        state <= ANALYZE;
                    end
                end

                ANALYZE: begin
                    // Find base address and determine coalescing type
                    base_address <= min_addr;
                    // All coalesced requests must be same type (read or write)
                    coalesce_is_write <= pending_is_write[0];  // Use first request type
                    state <= COALESCE;
                end

                COALESCE: begin
                    // Determine which requests can be coalesced
                    coalesce_mask <= {NUM_REQUESTS{1'b0}};
                    for (m = 0; m < NUM_REQUESTS; m = m + 1) begin
                        // Coalesce if sequential and same type
                        if (sequential_mask[m] && 
                            pending_is_write[m] == coalesce_is_write) begin
                            coalesce_mask[m] <= 1'b1;
                        end
                    end
                    num_coalesced <= count_ones;
                    state <= REQUEST;
                end

                REQUEST: begin
                    // Send coalesced request
                    coalesced_valid <= 1'b1;
                    coalesced_base_addr <= base_address;
                    coalesced_is_write <= coalesce_is_write;
                    coalesced_count <= num_coalesced;
                    
                    // Pack write data
                    if (coalesce_is_write) begin
                        for (m = 0; m < NUM_REQUESTS; m = m + 1) begin
                            if (coalesce_mask[m]) begin
                                // Place data at correct offset
                                coalesced_write_data[(pending_addr[m] - base_address) * DATA_BITS +: DATA_BITS] 
                                    <= pending_data[m];
                            end
                        end
                    end
                    
                    state <= WAIT;
                end

                WAIT: begin
                    if (coalesced_ready) begin
                        coalesced_valid <= 1'b0;
                        state <= DISTRIBUTE;
                    end
                end

                DISTRIBUTE: begin
                    // Distribute read data back to requesters
                    for (m = 0; m < NUM_REQUESTS; m = m + 1) begin
                        if (coalesce_mask[m]) begin
                            req_ready[m] <= 1'b1;
                            if (!coalesce_is_write) begin
                                // Extract data from correct offset
                                req_read_data[m] <= coalesced_read_data[
                                    (pending_addr[m] - base_address) * DATA_BITS +: DATA_BITS];
                            end
                            pending_mask[m] <= 1'b0;  // Mark as handled
                        end
                    end
                    
                    // Check if more requests pending
                    if (|(pending_mask & ~coalesce_mask)) begin
                        state <= ANALYZE;  // Process remaining
                    end else begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule

