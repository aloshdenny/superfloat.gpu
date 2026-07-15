`default_nettype none
`timescale 1ns/1ns

// Testbench wrapper for Atreides GPU
// Includes program and data memory models for cocotb testing
// Updated for enhanced architecture: 2 cores, 4 threads/block, one 2x2 systolic array per core

module tb_gpu #(
    parameter DATA_MEM_ADDR_BITS = 19,         // 1 MiB total data memory: 2^19 x 16-bit
    parameter DATA_MEM_DATA_BITS = 16,
    parameter DATA_MEM_NUM_CHANNELS = 4,       // 1 core × 4 threads
    parameter PROGRAM_MEM_ADDR_BITS = 12,      // Increased: 4096 instructions
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter PROGRAM_MEM_NUM_CHANNELS = 1,    // 1 per core
    parameter NUM_CORES = 1,                   // 1 core
    parameter THREADS_PER_BLOCK = 4,
    parameter SYSTOLIC_SIZE = 2,               // 2x2 systolic array
    parameter NUM_SYSTOLIC_ARRAYS = 2          // Two arrays per core
) (
    input wire clk,
    input wire reset,
    
    // Kernel Execution
    input wire start,
    output wire done,
    
    // Thread count input
    input wire [7:0] thread_count
);

    // Internal signals for memory interfaces (TB side arrays)
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
    wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];

    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;

    // DCR signals - directly connect to inputs for simplicity
    wire device_control_write_enable = (thread_count != 8'd0);
    wire [7:0] device_control_data = thread_count;

    // Flattened signals for GPU instantiation
    wire [(PROGRAM_MEM_NUM_CHANNELS*PROGRAM_MEM_ADDR_BITS)-1:0] program_mem_read_address_flat;
    wire [(PROGRAM_MEM_NUM_CHANNELS*PROGRAM_MEM_DATA_BITS)-1:0] program_mem_read_data_flat;
    wire [(DATA_MEM_NUM_CHANNELS*DATA_MEM_ADDR_BITS)-1:0] data_mem_read_address_flat;
    wire [(DATA_MEM_NUM_CHANNELS*DATA_MEM_DATA_BITS)-1:0] data_mem_read_data_flat;
    wire [(DATA_MEM_NUM_CHANNELS*DATA_MEM_ADDR_BITS)-1:0] data_mem_write_address_flat;
    wire [(DATA_MEM_NUM_CHANNELS*DATA_MEM_DATA_BITS)-1:0] data_mem_write_data_flat;

    genvar i_flat;
    generate
        for (i_flat = 0; i_flat < PROGRAM_MEM_NUM_CHANNELS; i_flat = i_flat + 1) begin : pack_program_mem
            // program_mem_read_address_flat is OUTPUT from DUT, so read from it into TB array
            assign program_mem_read_address[i_flat] = program_mem_read_address_flat[i_flat*PROGRAM_MEM_ADDR_BITS +: PROGRAM_MEM_ADDR_BITS];
            // program_mem_read_data_flat is INPUT to DUT, so drive it from TB array
            assign program_mem_read_data_flat[i_flat*PROGRAM_MEM_DATA_BITS +: PROGRAM_MEM_DATA_BITS] = program_mem_read_data[i_flat];
        end
        for (i_flat = 0; i_flat < DATA_MEM_NUM_CHANNELS; i_flat = i_flat + 1) begin : pack_data_mem
            // data_mem_read_address_flat is OUTPUT from DUT
            assign data_mem_read_address[i_flat] = data_mem_read_address_flat[i_flat*DATA_MEM_ADDR_BITS +: DATA_MEM_ADDR_BITS];
            // data_mem_read_data_flat is INPUT to DUT
            assign data_mem_read_data_flat[i_flat*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS] = data_mem_read_data[i_flat];
            // data_mem_write_address_flat is OUTPUT from DUT
            assign data_mem_write_address[i_flat] = data_mem_write_address_flat[i_flat*DATA_MEM_ADDR_BITS +: DATA_MEM_ADDR_BITS];
            // data_mem_write_data_flat is OUTPUT from DUT
            assign data_mem_write_data[i_flat] = data_mem_write_data_flat[i_flat*DATA_MEM_DATA_BITS +: DATA_MEM_DATA_BITS];
        end
    endgenerate

    // GPU Instance
    gpu #(
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .DATA_MEM_NUM_CHANNELS(DATA_MEM_NUM_CHANNELS),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .PROGRAM_MEM_NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .SYSTOLIC_SIZE(SYSTOLIC_SIZE),
        .NUM_SYSTOLIC_ARRAYS(NUM_SYSTOLIC_ARRAYS)
    ) gpu_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        
        .program_mem_read_valid(program_mem_read_valid),
        .program_mem_read_address_flat(program_mem_read_address_flat),
        .program_mem_read_ready(program_mem_read_ready),
        .program_mem_read_data_flat(program_mem_read_data_flat),
        
        .data_mem_read_valid(data_mem_read_valid),
        .data_mem_read_address_flat(data_mem_read_address_flat),
        .data_mem_read_ready(data_mem_read_ready),
        .data_mem_read_data_flat(data_mem_read_data_flat),
        .data_mem_write_valid(data_mem_write_valid),
        .data_mem_write_address_flat(data_mem_write_address_flat),
        .data_mem_write_data_flat(data_mem_write_data_flat),
        .data_mem_write_ready(data_mem_write_ready)
    );

    // =========================================================================
    // Program Memory Model
    // =========================================================================
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_memory [0:(1 << PROGRAM_MEM_ADDR_BITS)-1];
    
    reg program_mem_write_en;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_write_addr;
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_write_data_in;
    
    always @(posedge clk) begin
        if (program_mem_write_en) begin
            program_memory[program_mem_write_addr] <= program_mem_write_data_in;
        end
    end
    
    genvar p;
    generate
        for (p = 0; p < PROGRAM_MEM_NUM_CHANNELS; p = p + 1) begin : prog_mem_channels
            reg ready_reg;
            reg [PROGRAM_MEM_DATA_BITS-1:0] data_reg;
            
            always @(posedge clk) begin
                if (reset) begin
                    ready_reg <= 1'b0;
                    data_reg <= 0;
                end else begin
                    ready_reg <= program_mem_read_valid[p];
                    if (program_mem_read_valid[p]) begin
                        data_reg <= program_memory[program_mem_read_address[p]];
                    end
                end
            end
            
            assign program_mem_read_ready[p] = ready_reg;
            assign program_mem_read_data[p] = data_reg;
        end
    endgenerate

    // =========================================================================
    // Data Memory Model
    // =========================================================================
    reg [DATA_MEM_DATA_BITS-1:0] data_memory [0:(1 << DATA_MEM_ADDR_BITS)-1];
    
    genvar d;
    generate
        for (d = 0; d < DATA_MEM_NUM_CHANNELS; d = d + 1) begin : data_mem_channels
            reg read_ready_reg;
            reg write_ready_reg;
            reg [DATA_MEM_DATA_BITS-1:0] read_data_reg;
            
            always @(posedge clk) begin
                if (reset) begin
                    read_ready_reg <= 1'b0;
                    write_ready_reg <= 1'b0;
                    read_data_reg <= 0;
                end else begin
                    // Read handling
                    read_ready_reg <= data_mem_read_valid[d];
                    if (data_mem_read_valid[d]) begin
                        read_data_reg <= data_memory[data_mem_read_address[d]];
                    end
                    
                    // Write handling
                    write_ready_reg <= data_mem_write_valid[d];
                    if (data_mem_write_valid[d]) begin
                        data_memory[data_mem_write_address[d]] <= data_mem_write_data[d];
                    end
                end
            end
            
            assign data_mem_read_ready[d] = read_ready_reg;
            assign data_mem_read_data[d] = read_data_reg;
            assign data_mem_write_ready[d] = write_ready_reg;
        end
    endgenerate

    // =========================================================================
    // Memory initialization
    // =========================================================================
    integer i_init;
    initial begin
        for (i_init = 0; i_init < (1 << PROGRAM_MEM_ADDR_BITS); i_init = i_init + 1) begin
            program_memory[i_init] = 0;
        end
        for (i_init = 0; i_init < (1 << DATA_MEM_ADDR_BITS); i_init = i_init + 1) begin
            data_memory[i_init] = 0;
        end
    end

endmodule
