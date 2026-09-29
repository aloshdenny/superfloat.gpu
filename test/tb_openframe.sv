`default_nettype none
`timescale 1ns/1ns

// Chip-level testbench for superfloat_openframe. The host side (program and
// data memory, pin handshake) is modelled in cocotb: test/test_openframe_chip.py.
module tb_openframe #(
    parameter PROGRAM_CACHE_ENTRIES = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output wire        done,
    output wire [3:0]  core_active,
    output wire [15:0] bus_out,
    output wire        bus_sel,
    output wire        bus_we,
    output wire        bus_beat,
    output wire        bus_req,
    input  wire [15:0] bus_in,
    input  wire        bus_ack
);
    superfloat_openframe #(
        .PROGRAM_CACHE_ENTRIES(PROGRAM_CACHE_ENTRIES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .core_active(core_active),
        .bus_out(bus_out),
        .bus_sel(bus_sel),
        .bus_we(bus_we),
        .bus_beat(bus_beat),
        .bus_req(bus_req),
        .bus_in(bus_in),
        .bus_ack(bus_ack)
    );
endmodule
