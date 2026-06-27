`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for Load-Store Unit
// Provides direct access to LSU signals for cocotb testing
module tb_lsu #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16
) (
    input wire clk,
    input wire reset,
    input wire enable,
    
    // Core state
    input wire [2:0] core_state,
    
    // Memory control signals (from decoder)
    input wire mem_read_enable,
    input wire mem_write_enable,
    
    // Register inputs
    input wire [DATA_BITS-1:0] rs,  // Address for LDR/STR
    input wire [DATA_BITS-1:0] rt,  // Data for STR
    
    // LSU outputs
    output wire [1:0] lsu_state,
    output wire [DATA_BITS-1:0] lsu_out,
    
    // Memory interface outputs (directly connected for verification)
    output wire mem_read_valid,
    output wire [ADDR_BITS-1:0] mem_read_address,
    output wire mem_write_valid,
    output wire [ADDR_BITS-1:0] mem_write_address,
    output wire [DATA_BITS-1:0] mem_write_data
);

    // Memory interface signals
    wire mem_read_ready;
    wire [DATA_BITS-1:0] mem_read_data;
    wire mem_write_ready;

    // Instantiate the LSU
    lsu #(
        .ADDR_BITS(ADDR_BITS),
        .DATA_BITS(DATA_BITS)
    ) lsu_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .decoded_mem_read_enable(mem_read_enable),
        .decoded_mem_write_enable(mem_write_enable),
        .rs(rs),
        .rt(rt),
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data),
        .mem_write_valid(mem_write_valid),
        .mem_write_address(mem_write_address),
        .mem_write_data(mem_write_data),
        .mem_write_ready(mem_write_ready),
        .lsu_state(lsu_state),
        .lsu_out(lsu_out)
    );

    // Simple memory model for testing
    reg [DATA_BITS-1:0] memory [0:(1 << ADDR_BITS)-1];
    
    // Read response (1 cycle delay)
    reg read_ready_reg;
    reg [DATA_BITS-1:0] read_data_reg;
    
    always @(posedge clk) begin
        if (reset) begin
            read_ready_reg <= 1'b0;
            read_data_reg <= 0;
        end else begin
            read_ready_reg <= mem_read_valid;
            if (mem_read_valid) begin
                read_data_reg <= memory[mem_read_address];
            end
        end
    end
    
    assign mem_read_ready = read_ready_reg;
    assign mem_read_data = read_data_reg;
    
    // Write response (1 cycle delay)
    reg write_ready_reg;
    
    always @(posedge clk) begin
        if (reset) begin
            write_ready_reg <= 1'b0;
        end else begin
            write_ready_reg <= mem_write_valid;
            if (mem_write_valid) begin
                memory[mem_write_address] <= mem_write_data;
            end
        end
    end
    
    assign mem_write_ready = write_ready_reg;
    
    // Initialize memory with test pattern
    integer i;
    initial begin
        for (i = 0; i < (1 << ADDR_BITS); i = i + 1) begin
            memory[i] = i * 3 + 7;
        end
    end

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("build/waves/lsu.vcd");
        $dumpvars(0, tb_lsu);
    end

endmodule

