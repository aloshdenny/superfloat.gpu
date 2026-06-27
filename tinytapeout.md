# TinyTapeout Reference Notes
### Verified & Detailed — Sky130 Digital Flow (TT04–TT10)

---

## 1. Physical Tile Specifications

### Standard Tile Dimensions (TT04 onwards)

| Parameter | Value |
|---|---|
| Single tile (1×1) | 160 µm × 100 µm = 16,000 µm² (0.016 mm²) |
| Typical gate capacity | ~1,000 digital logic gates per tile |
| Maximum tile array | Configurable multi-tile (e.g. 2×2, 5×4) — not a fixed 8×2 cap |

> **Note:** Multi-tile sizes beyond 1×1 are available and have been used in practice (e.g. TT08 saw a 5×4 project). The exact maximum per shuttle is listed on the TinyTapeout pricing calculator at `app.tinytapeout.com/calculator`. Pricing is per tile, so larger arrays cost proportionally more.

---

## 2. I/O Pin Interface

The `tt_um_*` module wrapper exposes exactly **26 signal pins**:

| Signal | Count | Direction | Description |
|---|---|---|---|
| `clk` | 1 | Input | Global clock — delivered via `mprj_io[6]` |
| `rst_n` | 1 | Input | Active-low synchronous reset |
| `ena` | 1 | Input | Master enable — must be held HIGH for logic to run |
| `ui_in[7:0]` | 8 | Input | General-purpose digital inputs |
| `uo_out[7:0]` | 8 | Output | General-purpose digital outputs |
| `uio[7:0]` | 8 | Bidirectional | Controlled via `uio_oe[7:0]` output-enable mask |

The bidirectional bus is physically a single `uio[7:0]` bus but in RTL it is split across three signals in the wrapper: `uio_in[7:0]` (sampled input), `uio_out[7:0]` (driven output), and `uio_oe[7:0]` (output-enable per pin, HIGH = output).

---

## 3. Clock Specifications

- The clock is provided externally through the demo board (RP2040-based), configurable from **1 Hz to 66.5 MHz**.
- The `sky130_ef_io_gpiov2_pad` I/O pad macro used on TinyTapeout chips specifies a **maximum input frequency of 66 MHz**.
- There is a measured **insertion delay of up to ~10 ns** between the chip I/O pad and your design's clock input.
- The mux ring that selects between projects adds additional latency. Worst-case round-trip latency through the mux was measured at **~20 ns** on TT3.5 silicon.
- **Practical recommendation:** Design and simulate targeting **50 MHz or below** for general digital logic. For timing closure, set `CLOCK_PERIOD` to **20.0 ns** (50 MHz) or longer. Reserve 66 MHz claims only if your critical path timing analysis confirms it cleanly.

---

## 4. LibreLane / OpenLane Configuration Constraints

### 4.1 Physical Floorplan

```json
"FP_SIZING": "absolute",
"DIE_AREA": "0 0 160.0 100.0"
```

- `FP_SIZING` must be `"absolute"` for TinyTapeout macro blocks — do not use `"relative"`.
- `DIE_AREA` is hard-set to match your exact tile allocation in microns. For a 1×1 tile: `"0 0 160.0 100.0"`. Adjust the X dimension for multi-tile horizontal layouts (e.g. 2×1 = `"0 0 320.0 100.0"`).
- `FP_CORE_UTIL`: Typically **45–55%** for standard digital designs. Can push to 60–70% if routing is simple and congestion is low, but this risks DRC and routing overflow at higher densities. Default in TT config examples is 45%.

### 4.2 Timing Constraints

| Variable | Recommended Value | Notes |
|---|---|---|
| `CLOCK_PERIOD` | 20.0–40.0 ns | Corresponds to 25–50 MHz; match to your design target |
| `MAX_FANOUT_CONSTRAINT` | 6–8 | Caps capacitive load per net |
| `MAX_TRANSITION_CONSTRAINT` | 1.0–1.5 ns | Keeps signal edges clean |
| `MAX_CAPACITANCE_CONSTRAINT` | 0.20–0.25 pF | Per-node net cap limit |
| `PL_RESIZER_SETUP_SLACK_MARGIN` | 0.30–0.40 | Guards against PVT corner degradation |

### 4.3 Routing Layer Restriction

```json
"RT_MAX_LAYER": "met4"
```

This is **mandatory for all TinyTapeout macros.** Metal layer 5 (`met5`) is reserved by TinyTapeout's top-level power distribution network (PDN) and shuttle multiplexer. Any routing into `met5` from your macro will cause DRC failures at integration time. This is enforced hierarchically: the core uses `met5`, so your embedded macro can only use up to `met4`.

### 4.4 Hold-Time Margins (Critical for Tiled Arrays)

When stitching multiple PEs together into a systolic array, short inter-FMA data paths create severe hold-time risk. The data can propagate to the next register before the clock edge arrives if there is any clock skew across tiles. Force the router to aggressively insert delay buffers:

```json
"PL_RESIZER_HOLD_SLACK_MARGIN": 0.30,
"GRT_RESIZER_HOLD_SLACK_MARGIN": 0.30
```

These cause OpenROAD to prioritize hold fixing even at the cost of additional area.

---

## 5. Hidden Architectural Pitfalls

### 5.1 Clock Mux Latency — Real Operating Frequency

Your design does not connect directly to a chip I/O pad. The clock passes through TinyTapeout's global scan-chain multiplexer before reaching your tile. This mux introduces:

- **Insertion delay**: up to ~10 ns at the pad
- **Mux round-trip**: measured worst case ~20 ns on TT3.5

Even if your internal logic can close timing at 100 MHz in isolation, the system-level clock distribution limits practical operation to **~50–66 MHz**. For conservative, reliable operation, target **50 MHz or below** in your config and testbench.

### 5.2 Boundary Exclusion Zone — The 15 µm Rule

When placing your design inside a tile bounding box, you must leave the outermost **15 µm** of the tile perimeter completely free of logic cells and routing. This zone is reserved for:

- PDN power rails injected by TinyTapeout's top-level
- Tap cells automatically inserted during physical verification

Overlapping into this exclusion zone will cause DRC failures at factory sign-off and will reject your submission.

### 5.3 Unused Bidirectional Pins — Mandatory Grounding

If your design does not use the `uio` bus, you **must** explicitly drive both `uio_out` and `uio_oe` to zero in your top-level wrapper. Leaving them undriven (floating) will cause an LVS failure during Netgen/Yosys verification:

```verilog
assign uio_out = 8'b00000000;
assign uio_oe  = 8'b00000000; // All pins in high-impedance input mode
```

Similarly, any unused `uo_out` bits should be tied to GND. The official spec states: *"Do not leave any floating digital output pins in your design."*

### 5.4 Pin Placement for Hard Macros — Use a Pin Order Config

When compiling a macro (e.g. a FMA cell) as a reusable GDS/LEF block, you must explicitly constrain which edges of the macro block each port appears on. If you do not specify pin placement, OpenROAD places ports arbitrarily — inputs might land on the east edge and outputs on the north, breaking the data flow structure of a systolic array.

Use a `pin_order.cfg` or equivalent LibreLane pin constraint file:

```ini
# pin_order.cfg — directional port placement for systolic FMA
# West edge — data flowing in from left neighbor
a_in.*

# East edge — data flowing out to right neighbor
a_out.*

# North edge — weight/partial sum flowing in from top neighbor
b_in.*

# South edge — weight/partial sum flowing out to bottom neighbor
b_out.*
```

This ensures the data flow topology of your array is preserved structurally in the layout.

### 5.5 Power Distribution Network — Increasing Strap Density

For designs with high simultaneous switching activity (e.g. all PEs executing a MAC in the same cycle), the default PDN strap pitch may cause IR drop that manifests as logic glitches. To increase power strap density:

```json
"FP_PDN_VOFFSET": 5.0,
"FP_PDN_VPITCH": 20.0,
"FP_PDN_HOFFSET": 5.0,
"FP_PDN_HPITCH": 20.0
```

This lays down power straps every 20 µm horizontally and vertically, keeping the supply voltage stable across a densely active array. Note: In OpenLane 2.x, the variable names may differ (`FP_PDN_VVPITCH` → `FP_PDN_VPITCH`); check your toolchain version.

### 5.6 Power Net Exposure — LVS Power Pin Rule

When wrapping a custom macro inside TinyTapeout's `tt_um_*` top-level template, your GDS/LEF files must explicitly expose their power and ground pins (`VPWR`/`vccd1` and `VGND`/`vssd1`). If these nets are buried inside a black-box GDS without LEF pin declarations, the top-level OpenLane run cannot connect them to the outer pad ring.

Your structural wrapper instantiation must include:

```verilog
.VPWR(vccd1),
.VGND(vssd1),
```

Designs that omit this will pass RTL simulation cleanly but will fail LVS at the final GDS integration stage — the last step before tape-out submission. This is one of the most expensive failures to debug late in the flow.

### 5.7 Asynchronous Reset Synchronization

The `rst_n` signal from the TinyTapeout demo board is **fully asynchronous** to your design's clock. Feeding it directly into your core logic creates a metastability risk: if the reset deasserts within a clock setup/hold window, your pipeline state machine can enter an indeterminate state on power-up.

The fix is a two-flop reset synchronizer placed in your `tt_um_*` wrapper, before distributing reset to any internal modules:

```verilog
reg rst_sync_0, rst_sync_1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rst_sync_0 <= 1'b0;
        rst_sync_1 <= 1'b0;
    end else begin
        rst_sync_0 <= 1'b1;
        rst_sync_1 <= rst_sync_0;
    end
end

// Use rst_sync_1 as your internal synchronous reset throughout your design
```

`rst_sync_1` is now a safe, metastability-free reset signal synchronous to your clock domain.

### 5.8 Hold-Time Violations in Tiled Arrays — Detailed Explanation

This is distinct from the configuration margin in §4.4 and worth understanding at a deeper level.

When LibreLane hardens a single FMA in isolation, the clock tree is compact and hold-time is trivially met. When you stitch PEs together at the top level, the inter-FMA wires are extremely short (adjacent cells on the same tile or next tile). With even a small clock skew (a few hundred ps), the sending FMA's output will update and propagate to the receiving FMA's input **before** the receiving FMA's clock edge arrives. This is a hold-time violation that does not show up during single-FMA hardening.

The fix (from §4.4) forces OpenROAD to insert explicit delay buffers on these short inter-FMA paths during the top-level array routing pass. The `PL_RESIZER` and `GRT_RESIZER` hold slack margins tell the tool to pad nets that close timing too easily.

---

## 6. Module Naming and Documentation Rules

### 6.1 Top Module Naming

Your top-level module name **must start with `tt_um_`** and must be globally unique on the shuttle. Convention is:

```
tt_um_<github_username>_<project_name>
```

Example: `tt_um_aoxo_sf16_array`

### 6.2 info.yaml Requirements

The `info.yaml` file controls automated documentation rendering and submission validation. Key rules:

- Do not leave the `description` field as the default placeholder text (e.g. `"My cool test project"`). The CI linter will catch this and fail your build.
- The `pinout` section must exactly match the actual port assignments in your `tt_um_*` wrapper.
- The `top_module` field must exactly match the name of your top Verilog module.
- The `source_files` list must enumerate all `.v`/`.sv` files required for synthesis.

There is no documented hard "1000-line limit" on `info.yaml`. The real constraints are field validation (required fields present and non-empty) and documentation linting via TinyTapeout's GitHub Action workflows. Keep descriptions concise and accurate.

### 6.3 GitHub Repository Setup (Two Required Steps)

Just pushing code to GitHub is not sufficient to trigger the OpenLane cloud build. You must manually enable two settings:

**Step 1 — Enable GitHub Actions:**
Go to your repository → Actions tab → click "Enable Actions" (or "I understand my workflows, go ahead and enable them"). Without this, the GDS build workflow will never trigger.

**Step 2 — Enable GitHub Pages:**
Go to Settings → Pages → set the source to **"GitHub Actions"** (not a branch). TinyTapeout's backend autogenerates your chip documentation page using this Pages pipeline. If Pages is not set to Actions mode, the documentation step will silently fail.

---

## 7. Quick Configuration Reference

```json
{
  "DESIGN_NAME": "tt_um_yourname_yourproject",
  "VERILOG_FILES": "dir::src/*.v",
  "CLOCK_PORT": "clk",
  "CLOCK_PERIOD": 20.0,

  "FP_SIZING": "absolute",
  "DIE_AREA": "0 0 160.0 100.0",
  "FP_CORE_UTIL": 45,

  "RT_MAX_LAYER": "met4",

  "MAX_FANOUT_CONSTRAINT": 6,
  "MAX_TRANSITION_CONSTRAINT": 1.0,
  "MAX_CAPACITANCE_CONSTRAINT": 0.20,

  "PL_RESIZER_SETUP_SLACK_MARGIN": 0.30,
  "PL_RESIZER_HOLD_SLACK_MARGIN": 0.30,
  "GRT_RESIZER_HOLD_SLACK_MARGIN": 0.30,

  "FP_PDN_VOFFSET": 5.0,
  "FP_PDN_VPITCH": 20.0,
  "FP_PDN_HOFFSET": 5.0,
  "FP_PDN_HPITCH": 20.0
}
```

---

## 8. Submission Checklist

- [ ] `DIE_AREA` set to match your exact tile count dimensions
- [ ] `RT_MAX_LAYER` set to `"met4"` — never `met5`
- [ ] All unused `uio_out` and `uio_oe` bits explicitly assigned to `0`
- [ ] All unused `uo_out` bits tied to `0`
- [ ] Reset synchronizer present in top-level wrapper before any core logic
- [ ] Power pins (`vccd1`/`vssd1`) explicitly mapped in structural wrapper
- [ ] Pin order config file present for any hard macro blocks
- [ ] `CLOCK_PERIOD` set conservatively (≥ 20 ns recommended)
- [ ] Hold-slack margin variables set (`0.30`) for any tiled array designs
- [ ] `info.yaml` description filled in, pinout section matches actual ports
- [ ] Top module name starts with `tt_um_` and is unique
- [ ] GitHub Actions enabled on your repository
- [ ] GitHub Pages source set to "GitHub Actions"
- [ ] Local `docs/info.md` updated (not left as template placeholder)

---

*Sources: tinytapeout.com/specs, tinytapeout.com/specs/clock, tinytapeout.com/specs/gpio, tinytapeout.com/specs/analog, tinytapeout.com/faq, OpenLane documentation, OpenROAD project guides.*