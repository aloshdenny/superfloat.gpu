// Gate-level power run of a signed-off OpenFrame chip on one GPT-2 launch.
//
// The chip netlist (openframe_project_wrapper) and its tiles' netlists run on
// the sky130 cell models (-DFUNCTIONAL -DUNIT_DELAY=#1). This bench is the
// host: it holds the program and the launch's data window ($readmemh), answers
// every pin-bus beat as test_gpt2_bench.py does with HOST_LATENCY=0 (writes
// on the falling edge after REQ moves, reads one falling edge later), and
// launches the kernel as a board would. Activity is dumped from DUMP_START to
// DUMP_END cycles after START, for the chip's top level and tile 0
// (dump_scopes.vh, written by run_power.sh), and the launch's cycle count is
// printed. With STOP_AT_DUMP_END the run ends with the dump window.
//
// Pin map (src/openframe_project_wrapper.v): clk gpio[38], bus_ack 20,
// start 21, bus_in {gpio[40:39], gpio[37:24]}, bus_out gpio[15:0], sel 16,
// we 17, beat 18, req 19, done 22.
`timescale 1ns/1ps
`default_nettype none

module tb_chip_power;
    parameter integer THREADS     = 32;
    parameter integer DUMP_START  = 0;
    parameter integer DUMP_END    = 32'h7fffffff;
    parameter integer MAX_CYCLES  = 4000000;
    parameter integer STOP_AT_DUMP_END = 0;   // 1: finish at DUMP_END (outputs not checked)

    reg clk = 1'b0;
    always #10 clk = ~clk;                    // 50 MHz, the signoff clock

    reg [15:0] prog [0:511];
    reg [15:0] mem  [0:65535];
    initial begin
        $readmemh("prog.hex", prog);
        $readmemh("data.hex", mem);
    end

    reg        rst_b   = 1'b0;
    reg        start_r = 1'b0;
    reg        ack_r   = 1'b0;
    reg [15:0] bus_in_r = 16'd0;

    wire [43:0] gpio_in;
    assign gpio_in[19:0]  = 20'd0;
    assign gpio_in[20]    = ack_r;
    assign gpio_in[21]    = start_r;
    assign gpio_in[23:22] = 2'd0;
    assign gpio_in[37:24] = bus_in_r[13:0];
    assign gpio_in[38]    = clk;
    assign gpio_in[40:39] = bus_in_r[15:14];
    assign gpio_in[43:41] = 3'd0;

    wire [43:0] gpio_out, gpio_oeb, gpio_inp_dis, gpio_dm0, gpio_dm1, gpio_dm2;
    wire [43:0] gpio_analog_en, gpio_analog_sel, gpio_analog_pol, gpio_holdover;
    wire [43:0] gpio_ib_mode_sel, gpio_vtrip_sel, gpio_slow_sel;
    wire [43:0] analog_io, analog_noesd_io;

    openframe_project_wrapper dut (
        .por_l(1'b1), .porb_h(rst_b), .porb_l(rst_b), .resetb_h(rst_b), .resetb_l(rst_b),
        .analog_io(analog_io), .analog_noesd_io(analog_noesd_io),
        .gpio_analog_en(gpio_analog_en), .gpio_analog_pol(gpio_analog_pol),
        .gpio_analog_sel(gpio_analog_sel), .gpio_dm0(gpio_dm0), .gpio_dm1(gpio_dm1),
        .gpio_dm2(gpio_dm2), .gpio_holdover(gpio_holdover), .gpio_ib_mode_sel(gpio_ib_mode_sel),
        .gpio_in(gpio_in), .gpio_in_h(44'd0), .gpio_inp_dis(gpio_inp_dis),
        .gpio_loopback_one(44'hfffffffffff), .gpio_loopback_zero(44'd0),
        .gpio_oeb(gpio_oeb), .gpio_out(gpio_out), .gpio_slow_sel(gpio_slow_sel),
        .gpio_vtrip_sel(gpio_vtrip_sel), .mask_rev(32'd0)
    );

    wire [15:0] bus_out = gpio_out[15:0];
    wire bus_sel  = gpio_out[16];
    wire bus_we   = gpio_out[17];
    wire bus_beat = gpio_out[18];
    wire bus_req  = gpio_out[19];
    wire done     = gpio_out[22];

    // Host side of the handshake.
    reg        idle = 1'b1;
    reg        ack_pending = 1'b0;
    reg        req_seen = 1'b0;
    reg [15:0] waddr = 16'd0;
    integer    reads = 0, writes = 0;
    always @(negedge clk) begin
        if (idle)
            bus_in_r <= THREADS[15:0];
        if (ack_pending) begin
            ack_r       <= req_seen;
            ack_pending <= 1'b0;
        end else if (rst_b && !idle && (bus_req === 1'b0 || bus_req === 1'b1) && bus_req != ack_r) begin
            if (bus_we) begin
                if (!bus_beat) waddr <= bus_out;
                else begin mem[waddr] <= bus_out; writes = writes + 1; end
                ack_r <= bus_req;
            end else begin
                bus_in_r    <= bus_sel ? mem[bus_out] : prog[bus_out[8:0]];
                reads       = reads + 1;
                req_seen    <= bus_req;
                ack_pending <= 1'b1;
            end
        end
    end

    integer cycles = 0;
    reg     dumping = 1'b0;
    initial begin
        repeat (5) @(posedge clk);
        rst_b = 1'b1;
        repeat (8) @(posedge clk);
        start_r = 1'b1;
        @(posedge clk);
        cycles = 1;
        forever begin
            @(posedge clk);
            cycles = cycles + 1;
            if (cycles == 4) idle = 1'b0;
            if (!dumping && cycles >= DUMP_START && cycles < DUMP_END) begin
                dumping = 1'b1;
                $dumpfile("power.vcd");
                `include "dump_scopes.vh"
            end
            if (cycles % 1000 == 0) begin
                $display("cycle %0d reads %0d writes %0d", cycles, reads, writes);
                $fflush;
            end
            if (cycles == DUMP_END) begin
                $dumpoff;
                if (STOP_AT_DUMP_END) begin
                    $display("STOPPED cycles=%0d reads=%0d writes=%0d dump=%0d..%0d",
                             cycles, reads, writes, DUMP_START, DUMP_END);
                    $finish;
                end
            end
            if (cycles > 4 && done === 1'b1) begin
                if (cycles < DUMP_END) $dumpoff;
                $display("DONE cycles=%0d reads=%0d writes=%0d dump=%0d..%0d",
                         cycles, reads, writes, DUMP_START, (cycles < DUMP_END) ? cycles : DUMP_END);
                $writememh("data_out.hex", mem);
                $finish;
            end
            if (cycles >= MAX_CYCLES) begin
                $display("TIMEOUT cycles=%0d reads=%0d writes=%0d", cycles, reads, writes);
                $finish;
            end
        end
    end
endmodule

`default_nettype wire
