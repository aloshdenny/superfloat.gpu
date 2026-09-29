// SPDX-License-Identifier: Apache-2.0
// ChipFoundry OpenFrame user project wrapper for the Atreides SF16 GPU.
// Port list matches chipfoundry/openframe_user_project; do not change it.
//
// Pin map (pad edge from the fixed wrapper DEF):
//   gpio[14:0]   east   out  bus_out[14:0]
//   gpio[15]     north  out  bus_out[15]
//   gpio[16]     north  out  bus_sel      0 = program memory, 1 = data memory
//   gpio[17]     north  out  bus_we
//   gpio[18]     north  out  bus_beat     0 = address beat, 1 = write-data beat
//   gpio[19]     north  out  bus_req      toggles once per beat
//   gpio[20]     north  in   bus_ack      host sets ACK = REQ; pulled down
//   gpio[21]     north  in   start        pulled down
//   gpio[22]     north  out  done
//   gpio[23]     north  out  core_active[0]
//   gpio[37:24]  west   in   bus_in[13:0]
//   gpio[38]     south  in   clk          Caravel board oscillator pin
//   gpio[40:39]  south  in   bus_in[15:14]
//   gpio[43:41]  south  out  core_active[3:1]
// Reset: resetb_l (reset pad) AND porb_l (power-on reset), both active low.

`default_nettype none

`ifndef OPENFRAME_IO_PADS
`define OPENFRAME_IO_PADS 44
`endif

module openframe_project_wrapper (
`ifdef USE_POWER_PINS
    inout vdda,
    inout vdda1,
    inout vdda2,
    inout vssa,
    inout vssa1,
    inout vssa2,
    inout vccd,
    inout vccd1,
    inout vccd2,
    inout vssd,
    inout vssd1,
    inout vssd2,
    inout vddio,
    inout vssio,
`endif

    input porb_h,
    input porb_l,
    input por_l,
    input resetb_h,
    input resetb_l,
    input [31:0] mask_rev,

    input [`OPENFRAME_IO_PADS-1:0] gpio_in,
    input [`OPENFRAME_IO_PADS-1:0] gpio_in_h,
    output [`OPENFRAME_IO_PADS-1:0] gpio_out,
    output [`OPENFRAME_IO_PADS-1:0] gpio_oeb,
    output [`OPENFRAME_IO_PADS-1:0] gpio_inp_dis,

    output [`OPENFRAME_IO_PADS-1:0] gpio_ib_mode_sel,
    output [`OPENFRAME_IO_PADS-1:0] gpio_vtrip_sel,
    output [`OPENFRAME_IO_PADS-1:0] gpio_slow_sel,
    output [`OPENFRAME_IO_PADS-1:0] gpio_holdover,
    output [`OPENFRAME_IO_PADS-1:0] gpio_analog_en,
    output [`OPENFRAME_IO_PADS-1:0] gpio_analog_sel,
    output [`OPENFRAME_IO_PADS-1:0] gpio_analog_pol,
    output [`OPENFRAME_IO_PADS-1:0] gpio_dm2,
    output [`OPENFRAME_IO_PADS-1:0] gpio_dm1,
    output [`OPENFRAME_IO_PADS-1:0] gpio_dm0,

    inout [`OPENFRAME_IO_PADS-1:0] analog_io,
    inout [`OPENFRAME_IO_PADS-1:0] analog_noesd_io,

    input [`OPENFRAME_IO_PADS-1:0] gpio_loopback_one,
    input [`OPENFRAME_IO_PADS-1:0] gpio_loopback_zero
);
    // CF_gpio_config modes
    localparam [2:0] PAD_INPUT    = 3'd1;
    localparam [2:0] PAD_INPUT_PD = 3'd2;
    localparam [2:0] PAD_OUTPUT   = 3'd4;

    // Per-pad user-side signals
    wire [`OPENFRAME_IO_PADS-1:0] pad_out;   // value to drive (output pads)
    wire [`OPENFRAME_IO_PADS-1:0] pad_in;    // value from pad (input pads)

    // ------------------------------------------------------------------
    // Pad configuration: one CF_gpio_config per pad, mode from the pin map
    // ------------------------------------------------------------------

    genvar g;
    generate
        for (g = 0; g < `OPENFRAME_IO_PADS; g = g + 1) begin : pad
            // bus_ack and start pulled down; bus_in and clk plain inputs; the rest outputs
            localparam [2:0] MODE = (g == 20 || g == 21)  ? PAD_INPUT_PD :
                                    (g >= 24 && g <= 40)  ? PAD_INPUT    : PAD_OUTPUT;
            CF_gpio_config #(.MODE(MODE)) cfg (
                .io_out(pad_out[g]),
                .io_in(pad_in[g]),
                .io_oeb(1'b1),
                .gpio_zero(gpio_loopback_zero[g]),
                .gpio_one(gpio_loopback_one[g]),
                .gpio_in(gpio_in[g]),
                .gpio_dm({gpio_dm2[g], gpio_dm1[g], gpio_dm0[g]}),
                .gpio_inp_dis(gpio_inp_dis[g]),
                .gpio_oeb_out(gpio_oeb[g]),
                .gpio_out_val(gpio_out[g]),
                .gpio_analog_en(gpio_analog_en[g]),
                .gpio_analog_sel(gpio_analog_sel[g]),
                .gpio_analog_pol(gpio_analog_pol[g]),
                .gpio_ib_mode_sel(gpio_ib_mode_sel[g]),
                .gpio_vtrip_sel(gpio_vtrip_sel[g]),
                .gpio_slow_sel(gpio_slow_sel[g]),
                .gpio_holdover(gpio_holdover[g])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Pin map
    // ------------------------------------------------------------------
    wire        clk     = pad_in[38];
    wire        rst_n   = resetb_l & porb_l;
    wire        bus_ack = pad_in[20];
    wire        start   = pad_in[21];
    wire [15:0] bus_in  = {pad_in[40:39], pad_in[37:24]};

    wire [15:0] bus_out;
    wire        bus_sel, bus_we, bus_beat, bus_req, done;
    wire [3:0]  core_active;

    assign pad_out[14:0]  = bus_out[14:0];
    assign pad_out[15]    = bus_out[15];
    assign pad_out[16]    = bus_sel;
    assign pad_out[17]    = bus_we;
    assign pad_out[18]    = bus_beat;
    assign pad_out[19]    = bus_req;
    assign pad_out[21:20] = 2'b00;             // inputs
    assign pad_out[22]    = done;
    assign pad_out[23]    = core_active[0];
    assign pad_out[40:24] = 17'd0;             // inputs
    assign pad_out[43:41] = core_active[3:1];

    superfloat_openframe chip (
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

    // Tie the vccd1/vssd1 edge pins into the chip power grid (ChipFoundry macros).
    (* keep *) vccd1_connection vccd1_connection ();
    (* keep *) vssd1_connection vssd1_connection ();

endmodule

`default_nettype wire
