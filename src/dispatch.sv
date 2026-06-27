`default_nettype none
`timescale 1ns/1ns

// BLOCK DISPATCH
// > The GPU has one dispatch unit at the top level
// > Manages processing of threads and marks kernel execution as done
// > Sends off batches of threads in blocks to be executed by available compute cores
module dispatch #(
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Kernel Metadata
    input wire [7:0] thread_count,

    // Core States
    input wire [NUM_CORES-1:0] core_done,
    output reg [NUM_CORES-1:0] core_start,
    output reg [NUM_CORES-1:0] core_reset,
    output reg [8*NUM_CORES-1:0] core_block_id_flat,
    output reg [($clog2(THREADS_PER_BLOCK)+1)*NUM_CORES-1:0] core_thread_count_flat,

    // Kernel Execution
    output reg done
);
    // Internal unpacked arrays
    reg [7:0] core_block_id [NUM_CORES-1:0];
    reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0];
    
    // Flatten outputs
    localparam TC_BITS = $clog2(THREADS_PER_BLOCK) + 1;
    
    // Calculate the total number of blocks based on total threads & threads per block
    wire [7:0] total_blocks;
    assign total_blocks = 8'((32'(thread_count) + 32'(THREADS_PER_BLOCK) - 1) / 32'(THREADS_PER_BLOCK));

    // Keep track of how many blocks have been processed
    reg [7:0] blocks_dispatched; // How many blocks have been sent to cores?
    reg [7:0] blocks_done; // How many blocks have finished processing?
    reg start_execution; // EDA: Unimportant hack used because of EDA tooling

    integer i;
    
    // Flatten core_block_id and core_thread_count
    generate
        genvar g;
        for (g = 0; g < NUM_CORES; g = g + 1) begin : flatten_outputs
            always @(*) begin
                core_block_id_flat[(g+1)*8-1 -: 8] = core_block_id[g];
                core_thread_count_flat[(g+1)*TC_BITS-1 -: TC_BITS] = core_thread_count[g];
            end
        end
    endgenerate
    
    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            blocks_dispatched <= 0;
            blocks_done <= 0;
            start_execution <= 0;

            for (i = 0; i < NUM_CORES; i = i + 1) begin
                core_start[i] <= 0;
                core_reset[i] <= 1;
                core_block_id[i] <= 0;
                core_thread_count[i] <= TC_BITS'(THREADS_PER_BLOCK);
            end
        end else if (start) begin    
            // EDA: Indirect way to get @(posedge start) without driving from 2 different clocks
            if (!start_execution) begin 
                start_execution <= 1;
                for (i = 0; i < NUM_CORES; i = i + 1) begin
                    core_reset[i] <= 1;
                end
            end

            // If the last block has finished processing, mark this kernel as done executing
            if (blocks_done == total_blocks) begin 
                done <= 1;
            end

            // Use intermediate variables to correctly handle simultaneous
            // core dispatch/completion (non-blocking <= in a for loop would
            // cause both iterations to read the same old value).
            begin : dispatch_block
                reg [7:0] next_dispatched;
                next_dispatched = blocks_dispatched;
                
                for (i = 0; i < NUM_CORES; i = i + 1) begin
                    if (core_reset[i]) begin 
                        core_reset[i] <= 0;

                        // If this core was just reset, check if there are more blocks to be dispatched
                        if (next_dispatched < total_blocks) begin 
                            core_start[i] <= 1;
                            core_block_id[i] <= next_dispatched;
                            core_thread_count[i] <= (next_dispatched == total_blocks - 1) 
                                ? TC_BITS'(32'(thread_count) - (32'(next_dispatched) * 32'(THREADS_PER_BLOCK)))
                                : TC_BITS'(THREADS_PER_BLOCK);

                            next_dispatched = next_dispatched + 1;
                        end
                    end
                end
                
                blocks_dispatched <= next_dispatched;
            end

            begin : done_block
                reg [7:0] next_done;
                next_done = blocks_done;
                
                for (i = 0; i < NUM_CORES; i = i + 1) begin
                    if (core_start[i] && core_done[i]) begin
                        // If a core just finished executing its current block, reset it
                        core_reset[i] <= 1;
                        core_start[i] <= 0;
                        next_done = next_done + 1;
                    end
                end
                
                blocks_done <= next_done;
            end
        end
    end
endmodule
