//=============================================================================
// Module: CF_gpio_config
// Description: Sky130 GPIO Pad Configuration Wrapper for Efabless Openframe
//              Simple parameterized module - set MODE and forget about pad details
// License: Apache 2.0
//=============================================================================

`default_nettype none

module CF_gpio_config #(
  parameter [2:0] MODE = 3'd1  // 0=ANALOG, 1=INPUT, 2=INPUT_PD, 3=INPUT_PU, 4=OUTPUT, 5=BIDIR
)(
  //-------------------------------------------------------------------------
  // User Interface - Connect these to your design
  //-------------------------------------------------------------------------
  input  wire        io_out,       // Data to drive pad (used in OUTPUT/BIDIR modes)
  output wire        io_in,        // Data from pad (directly from gpio_in)
  input  wire        io_oeb,       // Output enable bar (BIDIR mode: 0=drive, 1=hi-z)

  //-------------------------------------------------------------------------
  // Openframe Interface - From openframe_project_wrapper
  //-------------------------------------------------------------------------
  input  wire        gpio_zero,    // Connection for 1'b0
  input  wire        gpio_one,     // Connection for 1'b1
  input  wire        gpio_in,      // Pad input (connect to gpio_in[n])

  //-------------------------------------------------------------------------
  // Openframe Interface - To openframe_project_wrapper pad config
  //-------------------------------------------------------------------------
  output wire [2:0]  gpio_dm,      // Drive mode {dm2, dm1, dm0}
  output wire        gpio_inp_dis, // Input disable
  output wire        gpio_oeb_out, // Output enable bar (active low)
  output wire        gpio_out_val, // Output value for gpio_out (includes pull mode values)
  output wire        gpio_analog_en,
  output wire        gpio_analog_sel,
  output wire        gpio_analog_pol,
  output wire        gpio_ib_mode_sel,
  output wire        gpio_vtrip_sel,
  output wire        gpio_slow_sel,
  output wire        gpio_holdover
);

  //-------------------------------------------------------------------------
  // Mode Definitions
  //-------------------------------------------------------------------------
  localparam [2:0] MODE_ANALOG   = 3'd0;  // Analog mode - input/output disabled
  localparam [2:0] MODE_INPUT    = 3'd1;  // Digital input, no pull resistor
  localparam [2:0] MODE_INPUT_PD = 3'd2;  // Digital input with pull-down
  localparam [2:0] MODE_INPUT_PU = 3'd3;  // Digital input with pull-up
  localparam [2:0] MODE_OUTPUT   = 3'd4;  // Digital output, push-pull
  localparam [2:0] MODE_BIDIR    = 3'd5;  // Bidirectional, direction from io_oeb

  //-------------------------------------------------------------------------
  // Drive Mode (dm[2:0]) - Based on Sky130 pad behavioral model
  //-------------------------------------------------------------------------
  // The Sky130 GPIO pad uses bufif1 primitives with specific strengths:
  //   dm=110: bufif1(strong1, strong0) - strong 1, strong 0
  //   dm=111: bufif1(pull1, pull0) - weak 1, weak 0
  //
  // For weak pull behavior:
  //   - Pull-DOWN (read 0 when floating): dm=111 with out=0 gives weak pull to 0
  //   - Pull-UP (read 1 when floating):   dm=111 with out=1 gives weak pull to 1
  //
  // MODE_ANALOG:   dm=000 (Hi-Z, analog mode)
  // MODE_INPUT:    dm=001 (Input only, no pull)
  // MODE_INPUT_PD: dm=111 (Weak pull to 0, requires oeb=0 and out=0)
  // MODE_INPUT_PU: dm=111 (Weak pull to 1, requires oeb=0 and out=1)
  // MODE_OUTPUT:   dm=110 (Strong push-pull)
  // MODE_BIDIR:    dm=110 (Strong push-pull, direction from io_oeb)
  //-------------------------------------------------------------------------
  assign gpio_dm = (MODE == MODE_ANALOG)   ? {gpio_zero, gpio_zero, gpio_zero} :  // 3'b000
                   (MODE == MODE_INPUT)    ? {gpio_zero, gpio_zero, gpio_one } :  // 3'b001 
                   (MODE == MODE_INPUT_PD) ? {gpio_one,  gpio_one,  gpio_one } :  // 3'b111 Weak output
                   (MODE == MODE_INPUT_PU) ? {gpio_one,  gpio_one,  gpio_one } :  // 3'b111 Weak output
                   (MODE == MODE_OUTPUT)   ? {gpio_one,  gpio_one,  gpio_zero} :  // 3'b110 Strong output
                   (MODE == MODE_BIDIR)    ? {gpio_one,  gpio_one,  gpio_zero} :  // 3'b110 Strong output
                                             {gpio_zero, gpio_zero, gpio_one };   // 3'b001 Default: INPUT

  //-------------------------------------------------------------------------
  // Input Disable
  //-------------------------------------------------------------------------
  // Disable input buffer for ANALOG and OUTPUT modes (not reading pad)
  assign gpio_inp_dis = (MODE == MODE_ANALOG) ? gpio_one :  // Disable input buffer for analog mode
                        (MODE == MODE_OUTPUT) ? gpio_one :  // Disable input buffer for output mode
                                                gpio_zero;  // Enable input buffer

  //-------------------------------------------------------------------------
  // Output Enable Bar (active low: 0=driving, 1=hi-z)
  //-------------------------------------------------------------------------
  // OUTPUT:   always driving (oeb=0)
  // BIDIR:    controlled by user's io_oeb signal
  // INPUT_PD: must drive to enable weak pull (oeb=0)
  // INPUT_PU: must drive to enable weak pull (oeb=0)
  // Others:   always hi-z (oeb=1)
  assign gpio_oeb_out = (MODE == MODE_OUTPUT)   ? gpio_zero :
                        (MODE == MODE_BIDIR)    ? io_oeb    :
                        (MODE == MODE_INPUT_PD) ? gpio_zero :  // Enable weak pull driver
                        (MODE == MODE_INPUT_PU) ? gpio_zero :  // Enable weak pull driver
                                                  gpio_one  ;

  //-------------------------------------------------------------------------
  // Fixed Configuration (safe defaults for all modes)
  //-------------------------------------------------------------------------
  assign gpio_analog_en   = gpio_zero;  // Enable amuxbus_a/b for ground/power
  assign gpio_analog_sel  = gpio_zero;  // Choose amuxbus_a (0) or amuxbus_b (1)
  assign gpio_analog_pol  = gpio_zero;  // Use amuxbus_a/b as ground (0) or power (1)
  assign gpio_ib_mode_sel = gpio_zero;  // Input buffer mode: VDDIO
  assign gpio_vtrip_sel   = gpio_zero;  // Trip point: CMOS
  assign gpio_slow_sel    = gpio_zero;  // Slew rate: fast
  assign gpio_holdover    = gpio_zero;  // No holdover

  //-------------------------------------------------------------------------
  // Output Value
  //-------------------------------------------------------------------------
  // For pull modes, drive the correct value to activate weak pull:
  //   INPUT_PD: out=0 to get weak pull to 0
  //   INPUT_PU: out=1 to get weak pull to 1
  // For OUTPUT/BIDIR: pass through user's io_out
  // For others: drive 0 (doesn't matter since oeb=1)
  assign gpio_out_val = (MODE == MODE_OUTPUT)   ? io_out    :
                        (MODE == MODE_BIDIR)    ? io_out    :
                        (MODE == MODE_INPUT_PD) ? gpio_zero :  // Drive 0 for weak pull-down
                        (MODE == MODE_INPUT_PU) ? gpio_one  :  // Drive 1 for weak pull-up
                                                  gpio_zero ;

  //-------------------------------------------------------------------------
  // Input Passthrough
  //-------------------------------------------------------------------------
  assign io_in = gpio_in;

endmodule

`default_nettype wire
