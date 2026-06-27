`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for Instruction Cache
// Provides direct access to cache signals for cocotb testing
module tb_cache #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter CACHE_SIZE = 16,
    parameter LINE_SIZE = 1
) (
    input wire clk,
    input wire reset,
    
    // CPU/Core interface (request side)
    input wire read_valid,
    input wire [ADDR_BITS-1:0] read_address,
    output wire read_ready,
    output wire [DATA_BITS-1:0] read_data,
    
    // Memory interface (backing store)
    output wire mem_read_valid,
    output wire [ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [DATA_BITS-1:0] mem_read_data
);

    // Instantiate the Cache
    cache #(
        .ADDR_BITS(ADDR_BITS),
        .DATA_BITS(DATA_BITS),
        .CACHE_SIZE(CACHE_SIZE),
        .LINE_SIZE(LINE_SIZE)
    ) cache_inst (
        .clk(clk),
        .reset(reset),
        .read_valid(read_valid),
        .read_address(read_address),
        .read_ready(read_ready),
        .read_data(read_data),
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data)
    );

    // Simple backing memory model for testing
    reg [DATA_BITS-1:0] backing_memory [0:(1 << ADDR_BITS)-1];
    
    // Memory model: 1 cycle delay response
    reg mem_ready_reg;
    reg [DATA_BITS-1:0] mem_data_reg;
    
    always @(posedge clk) begin
        if (reset) begin
            mem_ready_reg <= 1'b0;
            mem_data_reg <= 0;
        end else begin
            mem_ready_reg <= mem_read_valid;
            if (mem_read_valid) begin
                mem_data_reg <= backing_memory[mem_read_address];
            end
        end
    end
    
    assign mem_read_ready = mem_ready_reg;
    assign mem_read_data = mem_data_reg;
    
    // Initialize backing memory
    integer i;
    initial begin
        for (i = 0; i < (1 << ADDR_BITS); i = i + 1) begin
            backing_memory[i] = i * 2 + 1;  // Simple test pattern
        end
    end

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/cache.vcd");
        $dumpvars(0, tb_cache);
    end

endmodule

