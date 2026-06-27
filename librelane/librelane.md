# LibreLane Configuration Arguments Reference

> **Updated for `dev` branch (LibreLane 3.0):** This document reflects the latest CLI and configuration changes including the new `Chip` flow, enhanced KLayout/OpenROAD steps, renamed variables, and removed/deprecated options. See the [Deprecated Variable Names](#deprecated-variable-names) and [Removed Arguments](#removed-arguments) sections for migration guidance.

---

## Quick Start: Chip Flow

The `Chip` flow is a new top-level flow introduced in LibreLane 3.0, supporting pad ring generation, seal rings, and full-chip integration alongside the existing `Classic` flow.

```bash
# Classic flow (unchanged)
python3 -m librelane --pdk-root $HOME/.ciel ./designs/spm/config.json

# New Chip flow
python3 -m librelane --pdk-root $HOME/.ciel ./designs/chip/config.json --flow Chip
```

---

## 1. Core/Universal Variables

These variables are defined in `librelane/config/flow.py` and are available across all flows.

### PDK Variables

| Variable | Type | Description | PDK |
|----------|------|-------------|-----|
| `STD_CELL_LIBRARY` | str | Specifies the default standard cell library to be used under the specified PDK | Yes |
| `VDD_PIN` | str | The power pin for the cells | Yes |
| `GND_PIN` | str | The ground pin for the cells | Yes |
| `TECH_LEFS` | Dict[str, Path] | Map of corner patterns to technology LEF files | Yes |
| `PRIMARY_GDSII_STREAMOUT_TOOL` | str | Specify the primary GDSII streamout tool for this PDK (e.g., 'magic') | Yes |
| `DEFAULT_MAX_TRAN` | Optional[Decimal] | Default maximum transition value used in Synthesis and CTS (ns) | Yes |
| `DEFAULT_CORNER` | str | The IPVT corner to use for characterized lib files by default | Yes |
| `STA_CORNERS` | List[str] | List of fully qualified IPVT timing corners for multi-corner STA | Yes |
| `RT_MIN_LAYER` | str | The lowest metal layer to route on | Yes |
| `RT_MAX_LAYER` | str | The highest metal layer to route on | Yes |

### SCL Variables

| Variable | Type | Description | PDK |
|----------|------|-------------|-----|
| `SCL_GROUND_PINS` | List[str] | SCL-specific ground pins | Yes |
| `SCL_POWER_PINS` | List[str] | SCL-specific power pins | Yes |
| `TRISTATE_CELLS` | Optional[List[str]] | List of cell names/wildcards of tri-state buffers | Yes |
| `FILL_CELLS` | List[str] | List of cell names/wildcards of fill cells for fill insertion | Yes |
| `DECAP_CELLS` | List[str] | List of cell names/wildcards of decap cells for fill insertion | Yes |
| `LIB` | Dict[str, List[Path]] | Map from corner patterns to associated liberty files | Yes |
| `CELL_LEFS` | List[Path] | Path(s) to the cells' LEF file(s) | Yes |
| `CELL_GDS` | List[Path] | Path(s) to the cells' GDSII file(s) | Yes |
| `CELL_VERILOG_MODELS` | Optional[List[Path]] | Path(s) to cells' Verilog model(s) | Yes |
| `CELL_BB_VERILOG_MODELS` | Optional[List[Path]] | Path(s) to cells' black-box Verilog model(s) | Yes |
| `CELL_SPICE_MODELS` | Optional[List[Path]] | Path(s) to cells' SPICE model(s) | Yes |
| `CELL_CDLS` | Optional[List[Path]] | Circuit-design language view of the standard cell library | Yes |
| `SYNTH_EXCLUDED_CELL_FILE` | Path | Text file with list of cells to exclude from synthesis | Yes |
| `PNR_EXCLUDED_CELL_FILE` | Path | Text file with list of cells to exclude from synthesis AND PnR | Yes |
| `OUTPUT_CAP_LOAD` | Decimal | Capacitive load on output ports (fF) | Yes |
| `MAX_FANOUT_CONSTRAINT` | int | Max load output ports can drive, used as constraint on Synthesis/CTS | Yes |
| `MAX_TRANSITION_CONSTRAINT` | Optional[Decimal] | Max transition time on cell inputs (ns) | Yes |
| `MAX_CAPACITANCE_CONSTRAINT` | Optional[Decimal] | Maximum capacitance constraint (pF) | Yes |
| `CLOCK_UNCERTAINTY_CONSTRAINT` | Decimal | Clock uncertainty/jitter for timing analysis (ns) | Yes |
| `CLOCK_TRANSITION_CONSTRAINT` | Decimal | Clock transition/slew for timing analysis (ns) | Yes |
| `TIME_DERATING_CONSTRAINT` | Decimal | Derating factor to multiply path delays (%) | Yes |
| `IO_DELAY_CONSTRAINT` | Decimal | Percentage of clock period for input/output delays (%) | Yes |
| `SYNTH_DRIVING_CELL` | str | Cell to drive input ports, format: {cell}/{port} | Yes |
| `SYNTH_CLK_DRIVING_CELL` | Optional[str] | Cell to drive clock input ports, format: {cell}/{port} | Yes |
| `SYNTH_TIEHI_CELL` | str | Tie high cell, format: {cell}/{port} | Yes |
| `SYNTH_TIELO_CELL` | str | Tie low cell, format: {cell}/{port} | Yes |
| `SYNTH_BUFFER_CELL` | str | Buffer port for Yosys, format: {cell}/{input}/{output} | Yes |
| `PLACE_SITE` | str | Primary placement site as specified in technology LEF | Yes |
| `CELL_PAD_EXCLUDE` | List[str] | List of cells to exclude from cell padding | Yes |
| `DIODE_CELL` | Optional[str] | Diode cell for antenna repair, format: {cell}/{port} | Yes |
| `WELLTAP_CELL` | Optional[str] | Cell used for tap insertion | Yes |
| `ENDCAP_CELL` | Optional[str] | End-cap cell placed at sides of design | Yes |

### Option Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `DESIGN_DIR` | Path | Directory of the design (set via CLI) | - |
| `PDK_ROOT` | Path | Home path of all PDKs (set via CLI) | - |
| `DESIGN_NAME` | str | Name of top-level module | - |
| `PDK` | str | Process design kit name | sky130A |
| `CLOCK_PERIOD` | Decimal | Clock period for design (ns) | 10.0 |
| `CLOCK_PORT` | Union[None, str, List[str]] | Design's clock port name(s) | - |
| `CLOCK_NET` | Union[None, str, List[str]] | Net input to root clock buffer | - |
| `VDD_NETS` | Optional[List[str]] | Power nets/pins for power grid | - |
| `GND_NETS` | Optional[List[str]] | Ground nets/pins for power grid | - |
| `DIE_AREA` | Optional[Tuple[Decimal, Decimal, Decimal, Decimal]] | Specific die area (x0 y0 x1 y1) in um | - |
| `EXTRA_EXCLUDED_CELLS` | Optional[List[str]] | Additional cells to exclude from synthesis and PnR | - |
| `MACROS` | Optional[Dict[str, Macro]] | Dictionary of Macro definition objects | - |
| `EXTRA_LEFS` | Optional[List[Path]] | Miscellaneous LEF files to load | - |
| `EXTRA_VERILOG_MODELS` | Optional[List[Path]] | Miscellaneous Verilog models for synthesis | - |
| `EXTRA_SPICE_MODELS` | Optional[List[Path]] | Miscellaneous SPICE models | - |
| `EXTRA_CDLS` | Optional[List[Path]] | Miscellaneous CDL netlists | - |
| `EXTRA_LIBS` | Optional[List[Path]] | LIB files of pre-hardened macros for timing analysis | - |
| `EXTRA_GDS` | Optional[List[Path]] | GDS files of pre-hardened macros for tape-out | - |
| `FALLBACK_SDC` | Path | Fallback SDC file when step-specific SDC not defined | base.sdc |

### Pad Variables

| Variable | Type | Description | PDK |
|----------|------|-------------|-----|
| `PAD_GDS` | Optional[List[Path]] | Path(s) to IO pad GDS file(s) | Yes |
| `PAD_LEFS` | Optional[List[Path]] | Path(s) to IO pad LEF file(s) | Yes |
| `PAD_VERILOG_MODELS` | Optional[List[Path]] | Path(s) to IO pads' Verilog model(s) | Yes |
| `PAD_SPICE_MODELS` | Optional[List[Path]] | Path(s) to IO pads' SPICE model(s) | Yes |
| `PAD_CDLS` | Optional[List[Path]] | Circuit-design language view of IO pad library | Yes |
| `PAD_LIBS` | Optional[Dict[str, List[Path]]] | Map from corner patterns to pad liberty files | Yes |
| `PAD_CORNER` | Optional[List[str]] | Pad corner cell | Yes |
| `PAD_FILLERS` | Optional[List[str]] | List of pad filler cells | Yes |
| `PAD_SITE_NAME` | Optional[str] | Name of the pad site | Yes |
| `PAD_CORNER_SITE_NAME` | Optional[str] | Name of the corner site | Yes |
| `PAD_FAKE_SITES` | Optional[Dict[str, Tuple[Decimal, Decimal]]] | Fake pad sites and their dimensions | Yes |
| `PAD_BONDPAD_NAME` | Optional[str] | Name of bondpad cell | Yes |
| `PAD_BONDPAD_WIDTH` | Optional[Decimal] | Width of bondpad (um) | Yes |
| `PAD_BONDPAD_HEIGHT` | Optional[Decimal] | Height of bondpad (um) | Yes |
| `PAD_BONDPAD_OFFSETS` | Optional[Dict[str, Tuple[Decimal, Decimal]]] | Pad master to bondpad offset mapping | Yes |
| `PAD_PLACE_IO_TERMINALS` | Optional[List[str]] | Place I/O terminals for master/pin combinations | Yes |
| `PAD_EDGE_SPACING` | Optional[Decimal] | Distance from padring to die boundary (um) | 0 |

---

## 2. Common Step Variables

### IO Layer Variables (from common_variables.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `IO_PIN_H_LAYER` | str | Metal layer for horizontally-aligned pins (east/west) | PDK |
| `IO_PIN_V_LAYER` | str | Metal layer for vertically-aligned pins (north/south) | PDK |
| `IO_PIN_V_EXTENSION` | Decimal | Extends vertical pins outside die (um) | 0 |
| `IO_PIN_H_EXTENSION` | Decimal | Extends horizontal pins outside die (um) | 0 |
| `IO_PIN_V_THICKNESS_MULT` | Decimal | Multiplier for vertical pin thickness | 2 |
| `IO_PIN_H_THICKNESS_MULT` | Decimal | Multiplier for horizontal pin thickness | 2 |
| `IO_PIN_V_LENGTH` | Optional[Decimal] | Length of north/south pins (um) | PDK |
| `IO_PIN_H_LENGTH` | Optional[Decimal] | Length of east/west pins (um) | PDK |

### PDN Variables (from common_variables.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `PDN_SKIPTRIM` | bool | Skip metal trim step in pdngen | False |
| `PDN_CORE_RING` | bool | Enable core ring around design | False |
| `PDN_ENABLE_RAILS` | bool | Enable rails in power grid | True |
| `PDN_HORIZONTAL_HALO` | Decimal | Horizontal halo around macros (um) | 10 |
| `PDN_VERTICAL_HALO` | Decimal | Vertical halo around macros (um) | 10 |
| `PDN_MULTILAYER` | bool | Use multiple layers in power grid | True |
| `PDN_RAIL_OFFSET` | Decimal | Offset for PDN rails (um) | PDK |
| `PDN_VWIDTH` | Decimal | Strap width for vertical layer (um) | PDK |
| `PDN_HWIDTH` | Decimal | Strap width for horizontal layer (um) | PDK |
| `PDN_VSPACING` | Decimal | Intra-spacing of vertical straps (um) | PDK |
| `PDN_HSPACING` | Decimal | Intra-spacing of horizontal straps (um) | PDK |
| `PDN_VPITCH` | Decimal | Inter-distance of vertical straps (um) | PDK |
| `PDN_HPITCH` | Decimal | Inter-distance of horizontal straps (um) | PDK |
| `PDN_VOFFSET` | Decimal | Initial offset for vertical straps (um) | PDK |
| `PDN_HOFFSET` | Decimal | Initial offset for horizontal straps (um) | PDK |
| `PDN_CORE_RING_VWIDTH` | Decimal | Vertical layer width in core ring (um) | PDK |
| `PDN_CORE_RING_HWIDTH` | Decimal | Horizontal layer width in core ring (um) | PDK |
| `PDN_CORE_RING_VSPACING` | Decimal | Vertical layer spacing in core ring (um) | PDK |
| `PDN_CORE_RING_HSPACING` | Decimal | Horizontal layer spacing in core ring (um) | PDK |
| `PDN_CORE_RING_VOFFSET` | Decimal | Vertical layer offset in core ring (um) | PDK |
| `PDN_CORE_RING_HOFFSET` | Decimal | Horizontal layer offset in core ring (um) | PDK |
| `PDN_CORE_RING_CONNECT_TO_PADS` | bool | Connect core ring to pad pins | False |
| `PDN_CORE_RING_ALLOW_OUT_OF_DIE` | bool | Allow ring shapes outside die boundary | True |
| `PDN_RAIL_LAYER` | str | Metal layer for PDN rails | PDK |
| `PDN_RAIL_WIDTH` | Decimal | Width of PDN rails (um) | PDK |
| `PDN_HORIZONTAL_LAYER` | str | Horizontal PDN layer | PDK |
| `PDN_VERTICAL_LAYER` | str | Vertical PDN layer | PDK |
| `PDN_CORE_HORIZONTAL_LAYER` | Optional[str] | Horizontal PDN layer for core ring | PDK |
| `PDN_CORE_VERTICAL_LAYER` | Optional[str] | Vertical PDN layer for core ring | PDK |
| `PDN_EXTEND_TO` | Literal["core_ring", "boundary"] | How far stripes/rings extend | core_ring |
| `PDN_ENABLE_PINS` | bool | Promote power straps to block pins | True |

### Routing Layer Variables (from common_variables.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `RT_CLOCK_MIN_LAYER` | Optional[str] | Lowest layer for clock net routing | - |
| `RT_CLOCK_MAX_LAYER` | Optional[str] | Highest layer for clock net routing | - |
| `GRT_ADJUSTMENT` | Decimal | Routing capacity reduction (0-1) | 0.3 |
| `GRT_MACRO_EXTENSION` | int | GCells added to macro blockages | 0 |
| `GRT_LAYER_ADJUSTMENTS` | List[Decimal] | Layer-specific capacity reductions | PDK |

### Detailed Placement Variables (from common_variables.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `PL_OPTIMIZE_MIRRORING` | bool | Run optimize_mirroring pass | True |
| `PL_MAX_DISPLACEMENT_X` | int | Max X displacement during placement (um) | 500 |
| `PL_MAX_DISPLACEMENT_Y` | int | Max Y displacement during placement (um) | 100 |
| `DPL_CELL_PADDING` | int | Cell padding for detailed placement (sites) | PDK |

### Global Routing Variables (from common_variables.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `DIODE_PADDING` | Optional[int] | Diode cell padding (sites) | - |
| `GRT_ALLOW_CONGESTION` | bool | Allow congestion during global routing | False |
| `GRT_ANTENNA_REPAIR_ITERS` | int | Max iterations for global antenna repairs | 3 |
| `GRT_OVERFLOW_ITERS` | int | Max iterations for overflow reduction | 50 |
| `GRT_ANTENNA_REPAIR_MARGIN` | int | Margin for antenna repair (%) | 10 |
| `GRT_ANTENNA_REPAIR_JUMPER_ONLY` | bool | Only use jumpers for antenna repair | False |
| `GRT_ANTENNA_REPAIR_DIODE_ONLY` | bool | Only use diodes for antenna repair | False |

### Resizer Variables (from common_variables.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `RSZ_DONT_TOUCH_RX` | str | Regex for nets/instances to not touch | "$^" |
| `RSZ_DONT_TOUCH_LIST` | Optional[List[str]] | List of nets/instances to not touch | None |
| `RSZ_CORNERS` | Optional[List[str]] | Resizer step-specific override for PNR_CORNERS | - |

---

## 3. Synthesis Variables (Yosys)

### Verilog RTL Variables (from pyosys.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `VERILOG_FILES` | List[Path] | Paths of design's Verilog files | - |
| `VERILOG_DEFINES` | Optional[List[str]] | Preprocessor defines for Verilog | - |
| `VERILOG_POWER_DEFINE` | Optional[str] | Define for power/ground connections | USE_POWER_PINS |
| `VERILOG_INCLUDE_DIRS` | Optional[List[Path]] | Verilog `include` directories | - |
| `SYNTH_PARAMETERS` | Optional[List[str]] | Key-value pairs for `chparam` | - |
| `USE_SLANG` | bool | Use Slang frontend for SystemVerilog | False |
| `SLANG_ARGUMENTS` | Optional[List[str]] | Arguments for Slang frontend | - |

### Synthesis Common Variables (from pyosys.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `SYNTH_CHECKS_ALLOW_TRISTATE` | bool | Ignore multi-driver warnings for tri-state | True |
| `SYNTH_AUTONAME` | bool | Generate human-readable instance names | False |
| `SYNTH_STRATEGY` | Literal | ABC synthesis strategy | AREA 0 |
| `SYNTH_ABC_BUFFERING` | bool | Enable ABC cell buffering | False |
| `SYNTH_ABC_LEGACY_REFACTOR` | bool | Use legacy refactor command | False |
| `SYNTH_ABC_LEGACY_REWRITE` | bool | Use legacy rewrite command | False |
| `SYNTH_ABC_DFF` | bool | Pass DFFs through ABC optimization | False |
| `SYNTH_ABC_USE_MFS3` | bool | Use SAT-based remapping (experimental) | False |
| `SYNTH_ABC_AREA_USE_NF` | bool | Use delay-based mapper (experimental) | False |
| `SYNTH_DIRECT_WIRE_BUFFERING` | bool | Buffer directly connected wires | True |
| `SYNTH_SPLITNETS` | bool | Split multi-bit nets to single-bit | True |
| `SYNTH_SIZING` | bool | Enable ABC cell sizing | False |
| `SYNTH_HIERARCHY_MODE` | Literal | Hierarchy handling mode | flatten |
| `SYNTH_KEEP_HIERARCHY_MIN_COST` | Optional[int] | Gate count threshold for keep_hierarchy | - |
| `SYNTH_KEEP_HIERARCHY_INSTANCES` | Optional[List[str]] | Instances to keep hierarchy | - |
| `SYNTH_KEEP_HIERARCHY_MODULES` | Optional[List[str]] | Modules to keep hierarchy | - |
| `SYNTH_SHARE_RESOURCES` | bool | Enable resource sharing | True |
| `SYNTH_ADDER_TYPE` | Literal | Adder type for $add/$sub operators | YOSYS |
| `SYNTH_EXTRA_MAPPING_FILE` | Optional[Path] | Extra techmap file | - |
| `SYNTH_ELABORATE_ONLY` | bool | Elaborate only, no logic mapping | False |
| `SYNTH_MUL_BOOTH` | bool | Run booth pass for multiplication | False |
| `SYNTH_TIE_UNDEFINED` | Optional[Literal] | Tie undefined values (high/low) | low |
| `SYNTH_WRITE_NOATTR` | bool | Omit attributes from output netlist | True |
| `SYNTH_NORMALIZE_SINGLE_BIT_VECTORS` | bool | Convert [0:0] vectors to wires | True |
| `SYNTH_CLOCKGATE_MIN_WIDTH` | Optional[int] | Min FF group size for clock gating | - |
| `SYNTH_CLOCKGATE_POSEDGE_ICG` | Optional[str] | ICG cell for pos-edge FFs | PDK |
| `SYNTH_CLOCKGATE_NEGEDGE_ICG` | Optional[str] | ICG cell for neg-edge FFs | PDK |
| `YOSYS_LOG_LEVEL` | Literal | Yosys log level | ALL |
| `SYNTH_CORNER` | Optional[str] | Synthesis-specific timing corner | PDK |
| `SYNTH_SHOW` | bool | Generate graphviz DOT file | False |

### VHDL Synthesis Variables (from pyosys.py)

| Variable | Type | Description |
|----------|------|-------------|
| `VHDL_FILES` | List[Path] | Paths of design's VHDL files |
| `GHDL_ARGUMENTS` | Optional[List[str]] | Arguments for ghdl frontend |

---

## 4. Placement & Routing Variables (OpenROAD)

### OpenROAD Step Variables (from openroad.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `PNR_CORNERS` | Optional[List[str]] | Corners for PnR (uses STA_CORNERS if unset) | PDK |
| `SET_RC_VERBOSE` | bool | Echo set_rc commands | False |
| `LAYERS_RC` | Optional[Dict] | Custom RC values for metal layers | PDK |
| `VIAS_R` | Optional[Dict] | Custom resistance for via layers | PDK |
| `SIGNAL_WIRE_RC_LAYERS` | Optional[List[str]] | Layers for signal wire RC estimation | PDK |
| `CLOCK_WIRE_RC_LAYERS` | Optional[List[str]] | Layers for clock wire RC estimation | PDK |
| `PDN_CONNECT_MACROS_TO_GRID` | bool | Connect macros to top-level power grid | True |
| `PDN_MACRO_CONNECTIONS` | Optional[List[str]] | Explicit macro power connections | - |
| `PDN_ENABLE_GLOBAL_CONNECTIONS` | bool | Enable global connections in PDN | True |
| `PNR_SDC_FILE` | Optional[Path] | SDC file for PnR steps | - |
| `FP_DEF_TEMPLATE` | Optional[Path] | Template DEF file | - |
| `DEDUPLICATE_CORNERS` | bool | Cull duplicate IPVT corners | False |

### STA Variables (from openroad.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `STA_MACRO_PRIORITIZE_NL` | bool | Prioritize netlists+SPEF over LIB for macros | True |
| `STA_MAX_VIOLATOR_COUNT` | Optional[int] | Max violators in violator_list.rpt | - |
| `EXTRA_SPEFS` | Optional[List] | Deprecated: Use MACROS instead | - |
| `STA_THREADS` | Optional[int] | Max STA corners to run in parallel | - |

### CTS Variables (from openroad.py)

| Variable | Type | Description |
|----------|------|-------------|
| `CTS_CLK_BUFFERS` | List[str] | List of clock buffer cells |
| `CTS_SINK_BUFFER_MAX_CAP_DERATE_PCT` | Decimal | Cap derating for sink buffers |
| `CTS_DELAY_BUFFER_DERATE_PCT` | Decimal | Delay buffer derating |
| `CTS_OBSTRUCTION_AWARE` | bool | Enable obstruction-aware CTS |
| `CTS_BALANCE_LEVELS` | bool | Balance clock tree levels |
| `CTS_SINK_CLUSTERING_ENABLE` | bool | Enable sink clustering |
| `CTS_SINK_CLUSTERING_SIZE` | Optional[int] | Sink cluster size |
| `CTS_SINK_CLUSTERING_MAX_DIAMETER` | Optional[int] | Max cluster diameter |
| `CTS_MACRO_CLUSTERING_SIZE` | Optional[int] | Macro cluster size |
| `CTS_MACRO_CLUSTERING_MAX_DIAMETER` | Optional[int] | Max macro cluster diameter |
| `CTS_APPLY_NDR` | Optional[Literal] | Non-default rule strategy for clock nets |

### Floorplan Variables (from openroad.py)

| Variable | Type | Description |
|----------|------|-------------|
| `FP_SIZING` | Literal | Floorplan sizing mode (absolute/relative) |
| `CORE_AREA` | Optional[Tuple] | Core area (x0 y0 x1 y1) |
| `FP_FLIP_SITES` | Optional[List[str]] | Sites to flip |
| `PAD_FAKE_SITES` | Optional[Dict] | Fake pad sites |

### Global Placement Variables (from openroad.py)

| Variable | Type | Description |
|----------|------|-------------|
| `PL_TARGET_DENSITY` | Decimal | Target placement density |
| `PL_ROUTABILITY_DRIVEN` | bool | Enable routability-driven placement |
| `PL_TIMING_DRIVEN` | bool | Enable timing-driven placement |
| `PL_ROUTABILITY_MAX_DENSITY_PCT` | Optional[Decimal] | Max density for routability |
| `PL_KEEP_RESIZE_BELOW_OVERFLOW` | Optional[Decimal] | Keep resizing below overflow |
| `GPL_CELL_PADDING` | int | Cell padding for global placement |

### IO Placement Variables (from openroad.py)

| Variable | Type | Description |
|----------|------|-------------|
| `IO_PIN_PLACEMENT_MODE` | Literal | Pin placement mode |
| `IO_EXCLUDE_PIN_REGION` | Optional[List[Tuple]] | Regions to exclude for pins |
| `IO_PIN_CORNER_AVOIDANCE` | Optional[Decimal] | Corner avoidance distance |
| `IO_PIN_MIN_DISTANCE_IN_TRACKS` | Optional[int] | Min pin distance in tracks |

### Detailed Routing Variables (from openroad.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `DRT_SAVE_SNAPSHOTS` | bool | Save routing snapshots per iteration | False |
| `DRT_SAVE_DRC_REPORT_ITERS` | Optional[List[int]] | Iterations to save DRC reports (KLayout-readable XML) | - |
| `DRT_ANTENNA_REPAIR_ITERS` | int | Antenna repair iterations in detailed routing | 0 |
| `DRT_ANTENNA_REPAIR_MARGIN` | int | Antenna repair margin (%) | - |
| `DRT_ANTENNA_REPAIR_JUMPER_ONLY` | bool | Only use jumpers for antenna repair | False |
| `DRT_ANTENNA_REPAIR_DIODE_ONLY` | bool | Only use diodes for antenna repair | False |
| `NON_DEFAULT_RULES` | Optional[List[Path]] | Non-default routing rule files | - |
| `DRT_ASSIGN_NDR` | Optional[Dict] | Map of net names/patterns to non-default rules | - |

### Resizer Variables (from openroad.py)

| Variable | Type | Description |
|----------|------|-------------|
| `PL_RESIZER_SETUP_GATE_CLONING` | bool | Enable setup gate cloning |
| `PL_RESIZER_SETUP_BUFFERING` | Optional[bool] | Enable setup buffering |
| `PL_RESIZER_SETUP_BUFFER_REMOVAL` | Optional[bool] | Enable setup buffer removal |
| `PL_RESIZER_SETUP_REPAIR_TNS_PCT` | Optional[Decimal] | Setup TNS repair percentage |
| `PL_RESIZER_SETUP_MAX_UTIL_PCT` | Optional[Decimal] | Max utilization for setup repair |
| `PL_RESIZER_HOLD_REPAIR_TNS_PCT` | Optional[Decimal] | Hold TNS repair percentage |
| `PL_RESIZER_HOLD_MAX_UTIL_PCT` | Optional[Decimal] | Max utilization for hold repair |
| `GRT_RESIZER_SETUP_GATE_CLONING` | bool | GRT setup gate cloning |
| `GRT_RESIZER_SETUP_BUFFERING` | Optional[bool] | GRT setup buffering |
| `GRT_RESIZER_SETUP_BUFFER_REMOVAL` | Optional[bool] | GRT setup buffer removal |
| `GRT_RESIZER_SETUP_REPAIR_TNS_PCT` | Optional[Decimal] | GRT setup TNS repair |
| `GRT_RESIZER_SETUP_MAX_UTIL_PCT` | Optional[Decimal] | GRT setup max utilization |
| `GRT_RESIZER_HOLD_REPAIR_TNS_PCT` | Optional[Decimal] | GRT hold TNS repair |
| `GRT_RESIZER_HOLD_MAX_UTIL_PCT` | Optional[Decimal] | GRT hold max utilization |

---

## 5. Chip Flow Steps (New in LibreLane 3.0)

These steps are exclusive to the `Chip` flow and support full-chip integration with pad rings, seal rings, density checks, and more.

### OpenROAD.PadRing Variables

Generates a pad ring around the chip. Supported PDKs: `ihp-sg13g2`, `ihp-sg13cmos5l`, `gf180mcu`.

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `PAD_CFG` | Optional[Path] | Path to pad configuration Tcl file (`pad_cfg.tcl`) | - |
| `PAD_SOUTH` | Optional[List[str]] | Pad cells placed on south side | - |
| `PAD_EAST` | Optional[List[str]] | Pad cells placed on east side | - |
| `PAD_NORTH` | Optional[List[str]] | Pad cells placed on north side | - |
| `PAD_WEST` | Optional[List[str]] | Pad cells placed on west side | - |

> PDK-defined `PAD_*` variables set default pad configurations; `PAD_CFG` overrides them.

### KLayout.SealRing

Generates a seal ring around the chip perimeter. No user-configurable variables — behavior is fully PDK-driven. Supported PDKs: `gf180mcu`, `ihp-sg13g2`, `ihp-sg13cmos5l`.

### KLayout.Density

Performs density checks on the final GDSII layout.

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `klayout__density_error__count` | int | Number of density errors (output metric) | - |

### KLayout.Antenna

Generic KLayout-based antenna rule check. PDK-specific implementations are automatically selected.

### KLayout.Filler

Inserts fill cells at the chip level using KLayout. Behavior is PDK-driven.

---

## 6. Physical Verification Variables

### Magic Variables (from magic.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `MAGIC_DEF_LABELS` | bool | Read labels with DEF files | False |
| `MAGIC_GDS_POLYGON_SUBCELLS` | bool | Enable polygon subcells for GDS | False |
| `MAGIC_GDS_MERGE` | bool | Merge tiles into polygons during GDS write | True |
| `MAGIC_DEF_NO_BLOCKAGES` | bool | Ignore blockages in DEF | True |
| `MAGIC_INCLUDE_GDS_POINTERS` | bool | Include GDS pointers in mag files | False |
| `MAGICRC` | Path | Path to .magicrc file | PDK |
| `MAGIC_TECH` | Path | Path to Magic tech file | PDK |
| `MAGIC_PDK_SETUP` | Path | Path to PDK-specific setup file | PDK |
| `CELL_MAGS` | Optional[List[Path]] | Pre-processed cell views | PDK |
| `CELL_MAGLEFS` | Optional[List[Path]] | Pre-processed abstract LEF views | PDK |
| `MAGIC_CAPTURE_ERRORS` | bool | Capture Magic errors | True |
| `MAGIC_ZEROIZE_ORIGIN` | bool | Move layout origin to 0,0 | False |
| `MAGIC_DISABLE_CIF_INFO` | bool | Disable CIF info in GDS | True |
| `MAGIC_MACRO_STD_CELL_SOURCE` | Literal | Source for macro STD cells | macro |
| `MAGIC_DRC_USE_GDS` | bool | Run DRC on GDS vs DEF | True |
| `MAGIC_GDS_FLATGLOB` | Optional[List[str]] | Flatten cells by pattern | - |
| `MAGIC_DRC_MAGLEFS` | Optional[List[Path]] | Abstract views for DRC | - |
| `MAGIC_EXT_USE_GDS` | bool | Use GDS for SPICE extraction | False |
| `MAGIC_EXT_ABSTRACT_CELLS` | Optional[List[str]] | Abstract cells during extraction | - |
| `MAGIC_EXT_UNIQUE` | Literal | Extract unique option | all |
| `MAGIC_LEF_WRITE_USE_GDS` | bool | Use GDS for LEF writing | False |
| `MAGIC_WRITE_FULL_LEF` | bool | Include all shapes in LEF | False |
| `MAGIC_WRITE_LEF_PINONLY` | bool | Only mark port labels as pins | False |

### KLayout Variables (from klayout.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `KLAYOUT_TECH` | Path | Path to KLayout .lyt file | PDK |
| `KLAYOUT_PROPERTIES` | Path | Path to KLayout .lyp file | PDK |
| `KLAYOUT_DEF_LAYER_MAP` | Path | Path to KLayout LEF/DEF mapping | PDK |
| `KLAYOUT_CONFLICT_RESOLUTION` | Optional[Literal] | Cell name conflict resolution: `RenameCell`, `AddToCell`, `OverwriteCell`, `SkipNewCell` | RenameCell |
| `KLAYOUT_XOR_THREADS` | Optional[int] | Threads for XOR check | - |
| `KLAYOUT_XOR_IGNORE_LAYERS` | Optional[List[str]] | Layers to ignore in XOR | PDK |
| `KLAYOUT_XOR_TILE_SIZE` | Optional[int] | Tile size for XOR (um) | PDK |
| `KLAYOUT_DRC_RUNSET` | Optional[Path] | KLayout DRC runset | PDK |
| `KLAYOUT_DRC_OPTIONS` | Optional[Dict] | Options for DRC runset | PDK |
| `KLAYOUT_DRC_THREADS` | Optional[int] | Threads for KLayout DRC | - |

### KLayout Rendering Variables (KLayout.Render — new in dev)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `KLAYOUT_RENDER_GRID_VISIBLE` | bool | Show grid in rendered output | False |
| `KLAYOUT_RENDER_SHOW_RULER` | bool | Show ruler in rendered output | False |
| `KLAYOUT_RENDER_BACKGROUND_COLOR` | str | Background color (e.g., `"white"`, `"black"`) | PDK |
| `KLAYOUT_RENDER_TEXT_VISIBLE` | bool | Show text labels in rendered output | True |
| `KLAYOUT_RENDER_RESOLUTION` | int | Output resolution in DPI | PDK |
| `KLAYOUT_RENDER_OVERSAMPLING` | int | Anti-aliasing oversampling factor | PDK |

**Example:**
```json
{
  "KLAYOUT_RENDER_GRID_VISIBLE": true,
  "KLAYOUT_RENDER_SHOW_RULER": true,
  "KLAYOUT_RENDER_BACKGROUND_COLOR": "white",
  "KLAYOUT_RENDER_RESOLUTION": 300
}
```

### Netgen Variables

| Variable | Type | Description |
|----------|------|-------------|
| `LVS_CONNECT_BY_LABEL` | Optional[List[str]] | Connect nets by label in LVS |
| `LVS_INCLUDE_MOS_LW` | bool | Include MOS length/width in LVS |

---

## 7. Checker Variables

### Error Checkers (from checker.py)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `ERROR_ON_NL_ASSIGN_STATEMENTS` | bool | Error on assign statements in netlist | True |
| `ERROR_ON_UNMAPPED_CELLS` | bool | Error on unmapped cells after synthesis | True |
| `ERROR_ON_SYNTH_CHECKS` | bool | Error on synthesis check errors | True |
| `ERROR_ON_TR_DRC` | bool | Error on routing DRC violations | True |
| `ERROR_ON_MAGIC_DRC` | bool | Error on Magic DRC violations | True |
| `ERROR_ON_ILLEGAL_OVERLAPS` | bool | Error on illegal overlaps | True |
| `ERROR_ON_DISCONNECTED_PINS` | bool | Error on disconnected pins | True |
| `ERROR_ON_LONG_WIRE` | bool | Error on long wires | True |
| `ERROR_ON_XOR_ERROR` | bool | Error on XOR differences | True |
| `ERROR_ON_LVS_ERROR` | bool | Error on LVS errors | True |
| `ERROR_ON_PDN_VIOLATIONS` | bool | Error on power grid violations | True |
| `ERROR_ON_LINTER_ERRORS` | bool | Error on linter errors | True |
| `ERROR_ON_LINTER_WARNINGS` | bool | Error on linter warnings | False |
| `ERROR_ON_LINTER_TIMING_CONSTRUCTS` | bool | Error on timing constructs in lint | True |
| `WIRE_LENGTH_THRESHOLD` | Optional[Decimal] | Wire length threshold (um) | PDK |

### Timing Violation Checkers

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `TIMING_VIOLATION_CORNERS` | List[str] | Corners to check for timing violations | ["*tt*"] |
| `HOLD_VIOLATION_CORNERS` | List[str] | Corners to check for hold violations | ["*"] |

---

## 8. ECO Variables

| Variable | Type | Description |
|----------|------|-------------|
| `INSERT_ECO_BUFFERS` | Optional[Dict[str, List]] | ECO buffer insertion configuration |
| `INSERT_ECO_DIODES` | Optional[Dict[str, List]] | ECO diode insertion configuration |

---

## 9. Linter Variables (Verilator)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `LINTER_DISABLE_WARNINGS` | Optional[List[str]] | Disable specific linter warnings | - |
| `LINTER_DISABLE_WARNINGS_BLACKBOX` | Optional[List[str]] | Disable warnings for blackbox modules | - |
| `LINTER_VLT` | Optional[Path] | Verilator configuration file (.vlt) | - |

---

## Deprecated Variable Names

Many variables have deprecated names that are still supported for backwards compatibility. The configuration system automatically translates these to the new names. Some examples:

| New Name | Deprecated Name(s) |
|----------|-------------------|
| `IO_PIN_H_LAYER` | `FP_IO_HLAYER` |
| `IO_PIN_V_LAYER` | `FP_IO_VLAYER` |
| `IO_PIN_PLACEMENT_MODE` | `FP_IO_PLACEMENT_MODE` |
| `PDN_SKIPTRIM` | `FP_PDN_SKIPTRIM` |
| `PDN_CFG` | `FP_PDN_CFG` |
| `FILL_CELLS` | `FILL_CELL` |
| `DECAP_CELLS` | `DECAP_CELL` |
| `EXTRA_GDS` | `EXTRA_GDS_FILES` |
| `FALLBACK_SDC` | `FALLBACK_SDC_FILE`, `BASE_SDC_FILE`, `SDC_FILE` |
| `USE_SLANG` | `USE_SYNLIG` |
| `SYNTH_HIERARCHY_MODE` | `SYNTH_NO_FLAT`, `SYNTH_ELABORATE_FLATTEN`, `SYNTH_FLAT_TOP` |
| `PL_RESIZER_SETUP_GATE_CLONING` | `PL_RESIZER_GATE_CLONING` |
| `GRT_RESIZER_SETUP_GATE_CLONING` | `GRT_RESIZER_GATE_CLONING` |
| `RT_MIN_LAYER` | `DRT_MIN_LAYER` |
| `RT_MAX_LAYER` | `DRT_MAX_LAYER` |
| `VIAS_R` | `VIAS_RC` |

---

## Removed Arguments

The following arguments have been **removed** and are no longer supported. They are listed here for migration purposes.

| Removed Argument | Reason / Replacement |
|-----------------|----------------------|
| `DRT_MIN_LAYER` | Replaced by `RT_MIN_LAYER` (global routing layer control) |
| `DRT_MAX_LAYER` | Replaced by `RT_MAX_LAYER` |
| `VIAS_RC` | Replaced by `VIAS_R` with an updated format |
| `FP_DEF_TEMPLATE` | No longer a global variable; add to step-level config only |
| `GPIO_PAD_*` | Removed as unused |
| `USE_SYNLIG` | Replaced by `USE_SLANG` |
| `LIGHTER_DFF_MAP` | Replaced by `SYNTH_CLOCKGATE_POSEDGE_ICG` / `SYNTH_CLOCKGATE_NEGEDGE_ICG` |
| `SYNTH_ELABORATE_FLATTEN` | Folded into `SYNTH_HIERARCHY_MODE` |
| `PL_RESIZER_GATE_CLONING` | Renamed to `PL_RESIZER_SETUP_GATE_CLONING` |
| `GRT_RESIZER_GATE_CLONING` | Renamed to `GRT_RESIZER_SETUP_GATE_CLONING` |

### Removed Steps

| Removed Step | Reason |
|-------------|--------|
| `CVCRV.ERC` | Non-functional; removed |
| `OpenROAD.BasicMacroPlacement` | Non-functional; removed |

---

## Variable Types Reference

| Type | Description |
|------|-------------|
| `str` | String value |
| `int` | Integer value |
| `Decimal` | Decimal number (for precision) |
| `bool` | Boolean (true/false) |
| `Path` | File/directory path |
| `List[T]` | List of type T |
| `Dict[K, V]` | Dictionary with key K and value V |
| `Optional[T]` | Optional value of type T (may be null) |
| `Tuple[T1, T2, ...]` | Fixed-size tuple |
| `Literal[...]` | Enum-like, must be one of specified values |

---

## Validation and Error Handling (New in dev)

- **Paths starting with `~`** are rejected to avoid shell expansion issues. Use absolute paths or `$HOME`.
- **`KLAYOUT_CONFLICT_RESOLUTION`** defaults to `"RenameCell"` to prevent silent GDS cell overwrites (was previously `"AddToCell"`).
- **`HOLD_VIOLATION_CORNERS`** now defaults to `["*"]`, raising errors for hold violations on *all* corners (was previously `["*tt*"]`).
- **`MAGIC_DEF_LABELS`** defaults to `False`.
- OpenROAD steps now emit more detailed error reports for antenna violations and DRC errors.
- `KLayout.Density` uses `klayout__density_error__count` as an error metric.

---

## File Locations

Configuration variables are defined in the following files:

| File Path | Description |
|-----------|-------------|
| `librelane/config/flow.py` | Core PDK, SCL, Option, and Pad variables |
| `librelane/config/variable.py` | Variable class definition |
| `librelane/steps/common_variables.py` | Common step variables (PDN, IO, routing, etc.) |
| `librelane/steps/pyosys.py` | Synthesis-related variables |
| `librelane/steps/openroad.py` | OpenROAD PnR variables |
| `librelane/steps/magic.py` | Magic physical verification variables |
| `librelane/steps/klayout.py` | KLayout streamout/DRC/render variables |
| `librelane/steps/checker.py` | Checker step variables |
| `librelane/steps/odb.py` | ODB-based step variables |
| `librelane/flows/chip.py` | Chip flow definition and step ordering |
