`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER
// > Retrieves the instruction at the current PC from global data memory
// > Each core has it's own fetcher
// L0_ENTRIES > 0 keeps a direct-mapped buffer of recently fetched
// instructions, cleared with the block reset (a new launch's program is never
// served stale). A hit completes the fetch in one cycle without a request to
// the shared instruction cache; a kernel loop that fits the buffer runs from
// it after its first pass.
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter L0_ENTRIES = 32
) (
    input wire clk,
    input wire reset,
    input wire [2:0] core_state,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output reg mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,
    output reg [2:0] fetcher_state,
    output reg [PROGRAM_MEM_DATA_BITS-1:0] instruction
);
    localparam IDLE = 3'b000,
        FETCHING = 3'b001,
        FETCHED = 3'b010;

    localparam IDX_BITS = (L0_ENTRIES > 1) ? $clog2(L0_ENTRIES) : 1;
    localparam TAG_BITS = PROGRAM_MEM_ADDR_BITS - IDX_BITS;

    wire                             l0_hit;
    wire [PROGRAM_MEM_DATA_BITS-1:0] l0_word;
    generate
        if (L0_ENTRIES > 0) begin : g_l0
            reg [PROGRAM_MEM_DATA_BITS-1:0] l0_data [L0_ENTRIES-1:0];
            reg [TAG_BITS-1:0]              l0_tag  [L0_ENTRIES-1:0];
            reg [L0_ENTRIES-1:0]            l0_valid;
            wire [IDX_BITS-1:0] idx  = current_pc[IDX_BITS-1:0];
            wire [IDX_BITS-1:0] fidx = mem_read_address[IDX_BITS-1:0];
            assign l0_hit  = l0_valid[idx] && (l0_tag[idx] == current_pc[PROGRAM_MEM_ADDR_BITS-1:IDX_BITS]);
            assign l0_word = l0_data[idx];
            always @(posedge clk) begin
                if (reset) begin
                    l0_valid <= {L0_ENTRIES{1'b0}};
                end else if (fetcher_state == FETCHING && mem_read_ready) begin
                    l0_valid[fidx] <= 1'b1;
                    l0_tag[fidx]   <= mem_read_address[PROGRAM_MEM_ADDR_BITS-1:IDX_BITS];
                    l0_data[fidx]  <= mem_read_data;
                end
            end
        end else begin : g_no_l0
            assign l0_hit  = 1'b0;
            assign l0_word = {PROGRAM_MEM_DATA_BITS{1'b0}};
        end
    endgenerate

    always @(posedge clk) begin
        if (reset) begin
            fetcher_state <= IDLE;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            instruction <= {PROGRAM_MEM_DATA_BITS{1'b0}};
        end else begin
            case (fetcher_state)
                IDLE: begin
                    if (core_state == 3'b001) begin
                        if (l0_hit) begin
                            instruction   <= l0_word;
                            fetcher_state <= FETCHED;
                        end else begin
                            fetcher_state <= FETCHING;
                            mem_read_valid <= 1;
                            mem_read_address <= current_pc;
                        end
                    end
                end
                FETCHING: begin
                    if (mem_read_ready) begin
                        fetcher_state <= FETCHED;
                        instruction <= mem_read_data; // Store the instruction when received
                        mem_read_valid <= 0;
                    end
                end
                FETCHED: begin
                    if (core_state == 3'b010) begin
                        fetcher_state <= IDLE;
                    end
                end
                default: begin
                    fetcher_state <= IDLE;
                    mem_read_valid <= 0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
