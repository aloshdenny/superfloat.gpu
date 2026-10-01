# Chip evaluation reference

How every chip we harden is evaluated, whatever the PDK or fab program. It covers:

- the signoff gates;
- what to characterise beyond pass/fail;
- how to draft the workload models used to compare variants;
- which benchmarks and metrics to report, and how to measure them;
- the pitfalls found so far.

Findings from the Sky130 OpenFrame chips (SF16, FP16, BF16) are in [Findings to date](#findings-to-date), as worked examples. Detailed results stay in each chip's own document (`docs/openframe.md`, `docs/gpt2_benchmark.md`, `docs/double_wide.md`).

## At a glance

| Stage | Pass criterion, or what to record | Method |
|---|---|---|
| [Signoff gates](#1-signoff-gates) | Zero violations in every check and every corner | The flow's own checkers, plus the independent ones below |
| [Timing characterisation](#2-timing-characterisation) | Peak clock per corner and the block that sets it; the worst path of every block, classified | Signoff STA reports and metrics |
| [Functional verification](#3-functional-verification) | Bit-exact against a golden model; identical cycle counts at RTL and gate level | RTL and gate-level simulation through the chip's pins |
| [Workload benchmarks](#4-workload-benchmarks) | Latency, throughput, cycles and utilisation on a fixed set of scenarios | Kernels on real model data through the pins; launch schedule summed |
| [Power and energy](#5-power-and-energy) | Activity-based power by block and component; energy per token or operation | Gate-level VCD into OpenSTA with signoff parasitics |
| [Area and physical health](#6-area-and-physical-health) | Area, utilisation, IR drop, congestion, memory and runtime of the flow | Flow metrics; IR analysis with real supply entry |
| [System and I/O](#7-system-and-io) | Bus cycles per transfer and sensitivity to host latency; addressable window | Simulation sweeps |

Every number in a report is measured, and says where it came from (run tag, corner, workload).

## 1. Signoff gates

All of these are zero in every corner before a chip is called signed off. Record the run tag and tool versions with them.

- **Timing:** setup and hold slack ≥ 0 in every STA corner (Sky130: 9 = {min, nom, max} parasitics × {ss, tt, ff}); zero max-slew, max-capacitance and max-fanout violations.
- **Physical:** zero routing DRC, zero antenna violations, zero Magic and KLayout DRC, a clean Magic/KLayout XOR, LVS clean, and the fab's manufacturability check passing.
- **Connectivity:** disconnected pins accounted for one by one (for example, a harness's unused pad pins); power-grid check clean.
- **Macros:** each macro's own signoff is complete before the chip's. The chip is timed against macro timing models **with hold arcs** (see [Findings](#findings-to-date)).
- **Independent checks**, not only the flow's:
  - gate-level simulation of the signed-off netlist (section 3);
  - IR drop with the real supply entry points (section 6);
  - STA of the chip with the macros' final views.

## 2. Timing characterisation

Pass/fail at the target clock is not the whole picture. For every block (macro and top level) and every corner, record the following.

**Peak clock.**
- Tmin = T − WNS (worst negative or positive setup slack), and Fmax = 1 / Tmin, taken over all blocks. Name the block that limits it.
- This holds for single-cycle paths with fixed I/O delays and clock uncertainty.
- Report the worst corner (guaranteed peak) and the typical corner separately.

**What limits it.** Classify the worst path of each block:

| Class | Signature | Lever |
|---|---|---|
| Logic depth | Many cells, short wires | Pipelining, faster arithmetic |
| Wire | Chains of repair buffers (`wire*`, `max_cap*`), long distance between start and end | Floorplan, placement density, registers near consumers |
| I/O constraint | Ends at a port, slack set by `set_input_delay` / `set_output_delay` | Revisit the board-level budget; asynchronous handshakes may not need it |
| Clock | Large skew or insertion delay, delay chains on the clock | CTS settings, clock-pin buffering |
| Reset | Reset distribution net | Register the reset per block |

**Record the path**, not just the slack:
- startpoint and endpoint, named from the netlist (the Q-pin net names identify the RTL signal);
- total delay;
- the share of wire versus logic.

**A slack at a relaxed target is not the design's capability.** The tools stop optimising once a block meets its clock. To compare variants (for example number formats) on speed, harden each one at a sweep of target clocks and report the fastest that closes.

**Hold:**
- report hold slack at the fast corners, and at the corner that is actually worst, which need not be min_ff;
- check hold into macros through models that carry hold arcs;
- check hold out of synchronisers.

**Reset:** report the reset arc into every macro. If a macro registers its reset, note it; the arc moves.

## 3. Functional verification

- **Golden models are bit-exact.** They match the hardware's arithmetic exactly:
  - rounding mode;
  - flush-to-zero;
  - saturation;
  - canonical zeros;
  - fused versus separate rounding;
  - the order of accumulation.
  A reference that is "close" hides bugs.
- **Through the pins.** Drive the chip as a board would, through its real pin protocol, with a host model.
  - Use a deterministic host latency for cycle counts, and a randomised one for robustness.
- **Gate level.** Simulate the signed-off netlists on the cell models (Sky130: `-DFUNCTIONAL -DUNIT_DELAY=#1`, so flops have a 1 ns clock-to-Q and gates are zero-delay).
  - Outputs must match the golden model, and cycle counts must match RTL.
  - Physical-only cells (fill, decap, tap) can be left out of the simulation netlist.
- **Real data.** Use the workload's real operands (section 4), not only random vectors. Real distributions exercise exponents, saturation and rounding differently.
- **Every variant.** Run every test for every variant: each number format, each tile count.

## 4. Workload benchmarks

### Drafting the comparison models

When variants are compared (formats, array sizes, chips), each runs the same model on the same scenarios. When drafting the model:

- **Same model, per-variant encoding.**
  - Convert the model's real weights once per variant, with the hardware's own conversion semantics.
  - For fixed-point formats, scale each tensor by a power of two so it fits, and keep the exponent on the host. Then the variants differ only in what the hardware does, not in the data.
- **Real activations.**
  - Take activations from a reference run of the full-precision model on a real prompt.
  - Switching activity, and so power, depends on the values.
- **Decide what runs where, and say so.**
  - List the operations the ISA cannot do (Sky130 v1: exp, rsqrt, GELU, general divide). Assign them to the host, or to on-chip approximations.
  - Report the split and its cost: the bus traffic it adds or saves.
  - Do not let a missing instruction silently change the model.
- **Shape the model to the hardware's limits.** Record each limit and how the model meets it:
  - array size (tile to it, pad the rest);
  - addressable data window (map operands per launch);
  - launch limits (thread-count width);
  - instruction-cache size (loops must fit);
  - register count.
- **Lay data out for the kernel.** Store operands in host memory in the order the kernel reads them, as a one-time conversion, so that pointers step simply. Count that conversion as model preparation, not inference.
- **Separate quality from performance.** Unless quality is the question, state that it is not measured. If it is, measure it on a held-out set with the bit-exact datapath.
- **Fix the scenarios before measuring:**
  - prompt lengths (at least short, medium and long);
  - generated tokens;
  - batch size;
  - the way context grows during decode (attention cost grows with it).

### Metrics

| Metric | Definition |
|---|---|
| Prefill (encode) time | The prompt through every layer, ending with the logits of its last token |
| Time to first token (TTFT) | Prefill + host operations + sampling of the first token |
| Time per output token (TPOT) | One decode step at a given context length (report the range over the scenario) |
| End-to-end response | TTFT + every further decode step, for the scenario's prompt and output lengths |
| Throughput | Decode tokens per second; prefill tokens per second |
| Cycles | Per launch, per token, per scenario; with the clock, these give every time above |
| Cycles per bus transfer | Cycles ÷ bus beats: shows how bandwidth-bound the chip is |
| MAC utilisation | MACs performed ÷ (peak MACs per cycle × cycles) |
| Bytes per token | Over the chip's I/O, split into weights and activations |
| Energy | Per token and per scenario; also per MAC (pJ/MAC) for comparison across designs |
| Peak clock | From section 2, at the worst and the typical corner |

Report every time at the chip's own guaranteed peak clock, and also at a common clock. The common clock separates the architecture's effect from the clock's.

### Measured and modelled

- **Simulate the dominant shapes exactly.** Every launch shape that carries most of the time is simulated in full, through the pins, with outputs checked.
- **Fit only minor shapes.** Rare shapes (for example attention at each context length) may come from a fit over simulated ones, such as cycles = a + b × bus beats. Report the fit's worst residual, and how many launches used it.
- **Sweep host latency.** A real host (MCU, FPGA, bridge) answers more slowly than a testbench. Measure cycles at 0, 1, 2 and 4 cycles of host delay, and report the slope.
- **Keep the schedule in code.** The list of launches per scenario is code, so the totals can be re-derived and audited.

## 5. Power and energy

- **Activity-based, not vectorless.**
  - Run the signed-off netlists at gate level on the workload's kernels.
  - Dump switching activity for a window in steady state, the loop where the chip spends its time.
  - Read it into OpenSTA (`read_vcd`, `report_power`) with each block's signoff SPEF and SDC, at the typical corner.
  - Signoff's vectorless figure (default activity) is a placeholder; report it only for comparison.
- **Check the annotation, every time.**
  - OpenSTA annotates **pins**: a VCD variable inside a cell instance's scope (`top/dut/<instance>/<pin>`). Net names do not annotate.
  - A scope or name mismatch silently falls back to default activity.
  - Report the annotated / total pin count. It should be close to 100%; explain the rest.
    - v1 chip top level: 17,975 of 19,013. The remainder: 354 macro pins (the macros are analysed separately), 548 tie-cell outputs (constant), 75 CTS dummy loads and 61 pins on port-vector nets, which take propagated activity.
  - Known traps:
    - Escaped instance names lose their backslash in Icarus scopes (`chip.gpu_inst.tiles[0].tile`).
    - A top level dumped as nets must be rewritten as its cells' pins (`test/gpt2/power/vcd_pins.py`).
    - Several `$dumpvars` calls give several scope trees.
- **Dump size.** A full-chip gate-level dump can run to about 100 KB per cycle. Window the dump (10,000 cycles is plenty in a steady loop) and stop the simulation at the window's end.
- **Hierarchy.** Report power per block (top level, each macro or one macro × count) and per component (clock tree, sequential, combinational, leakage).
  - The split shows the lever: a clock-dominated block wants clock gating, not a cheaper datapath.
- **Energy:**
  - energy = power × time for each phase (prefill, decode), from the phase's own kernel;
  - dynamic power scales with the clock, so energy per token is nearly independent of it; add leakage × time;
  - report idle power (clock running, no launch) if the chip waits on the host for long.
- **State what is outside the netlists:**
  - I/O pads and the padframe;
  - the host;
  - off-chip memory.

## 6. Area and physical health

- **Area:**
  - die area, core area and standard-cell area;
  - utilisation per block;
  - the unit that dominates (for example the PE) at hardened size.
  - Utilisation affects timing: a sparse block has longer wires.
- **IR drop:**
  - analyse with the real supply entry (sources at the pads or ports, not an ideal grid) and the signoff power per macro;
  - report the worst drop per net and the worst combined drop at any macro;
  - record the grid's settings (widths, pitches, buses, supply ties) with the result.
- **Congestion:**
  - report global-routing overflow, the extra iterations it took, and detailed-routing violations per iteration;
  - record the placement density target and cell padding.
- **Flow resources:** peak memory and runtime per step. On a shared server, an unexpected jump flags a problem in the design (one step going from 1 GiB to 27 GiB did).

## 7. System and I/O

- **Bus or I/O throughput:** cycles per transfer at the ideal host, and the slope against host latency.
- **Bytes per operation:**
  - with 16-bit data on a 16-bit bus, every weight is one transfer;
  - narrower formats or wider buses change speed more than arithmetic does, when the chip is bandwidth-bound.
- **Addressing:** the data window the chip can address and what the host must map per launch.
- **Launch overhead:** start/done handshake and program fetch, per launch and as a share of a token.

## Reporting template

One results card per chip and variant:

| Field | Content |
|---|---|
| Identity | Chip, variant, run tags (macro and chip), tool versions, PDK version |
| Signoff | Pass/fail per gate (section 1), corners |
| Peak clock | Worst and typical corner, limiting block, worst path class |
| Worst paths | Per block: start → end (RTL names), delay, class |
| Function | Gate-level result, cycle-count match |
| Benchmarks | The metrics table for every scenario, at the chip's peak clock and at the common clock |
| Power | Per block and component, annotation coverage, workload and window |
| Energy | Per token, per scenario, pJ/MAC |
| Area | Die, cells, utilisation, dominant unit |
| Physical | IR drop, congestion, flow peak memory |
| Notes | Anything excluded (pads, host), anything modelled rather than simulated |

## Findings to date

From the Sky130 OpenFrame chips (v1: SF16, FP16, BF16; four tiles, an 8 × 8 array per tile, a 16-bit pin bus). Sources: `docs/openframe.md`, `docs/gpt2_benchmark.md`, `docs/pe_optimization.md`, `docs/double_wide.md`.

### Clock and worst paths

| | SF16 | FP16 | BF16 |
|---|---|---|---|
| Peak clock, worst corner (ss, 100 °C, 1.60 V) | 51.9 MHz | 55.7 MHz | 54.1 MHz |
| Limiting block, worst corner | Tile | Tile | Tile |
| Tile worst path, worst corner | LSU address register → activation output, through a chain of long-wire buffers (wire-dominated) | Inside an FP PE adder (`ad_hi` → `s_mag`) | FP activation unit (`s_mag` → `act_out`) |
| Peak clock, typical corner (tt, 25 °C, 1.80 V) | 87.9 MHz | 88.8 MHz | 87.1 MHz |
| Limiting path, typical corner | Chip: `bus_req` output, under a 4 ns output-delay budget | Same | Same |
| Tile utilisation | 0.423 | 0.561 | 0.493 |

- **SF16's arithmetic is not its limit.** The SF16 tile is the sparsest of the three, and its worst path is wire, not logic.
- **None of these clocks is a format's capability.** All three were closed at 20 ns only (section 2).
- **At the typical corner the limit is an assumption.** It is the board-interface budget on an asynchronous handshake, not logic. The tiles' own typical-corner limit is about 107–119 MHz.

### Workload behaviour

GPT-2 small runs with weights streamed from the host.

- **Cycles are identical across formats.** The pipeline is format-independent: every instruction has the same stages, and FMA is 2 execute cycles in each format.
  - Measured: a K = 768, 10-block decode launch takes 545,243 cycles on all three.
- **The chip is bandwidth-bound.**
  - Decode costs about 1.125 bus reads per weight at about 7.8 cycles per transfer.
  - A K = 768, 10-block decode launch does 61,440 MACs in 545,243 cycles: 0.11 MACs per cycle against a peak of 256, or 0.04% utilisation.
  - Host latency matters directly. The 4-block decode launch takes 210,885 / 237,059 / 263,328 / 307,663 cycles at 0 / 1 / 2 / 4 cycles of host delay.
- **Power is clock and flops.** Gate-level, SF16 tile on a decode launch: clock tree 66%, sequential 33%, combinational about 1% (the datapath is mostly idle).
  - Format differences show up through flop count and clock-tree size more than through the arithmetic.
  - PE area at 20 ns: 16,611 / 21,775 / 18,161 µm².
  - PE power at half-rate MACs: 0.782 / 1.330 / 1.180 mW (SF16 / FP16 / BF16).

### Hardening lessons

- **Hold into macros was not checked at first.**
  - The tile SDC false-pathed port hold, so the tile's timing model had no hold arcs; the chip failed hold into the tile by 0.21 ns once checked.
  - Generate macro models with an SDC that keeps hold, and check that the arcs exist.
- **Reset into FP tiles failed setup.**
  - Fix: a registered reset stage per block, for the units that do not need the early reset.
- **Resizer memory grows with corners.**
  - With all 9 corners, repair_design passed 15 GB on the double-wide die.
  - Repair against the limiting corners only (max_ss for setup; min_ff and max_ff for hold) and keep signoff on all 9.
  - Hold proved worst at max_ff into a macro, not at min_ff.
- **Magic LEF writing read the macros' GDS (22 GiB).** Read macros as LEF abstracts for the chip's LEF and its LVS extraction.
- **Cross-die requests.**
  - A request from a tile 3 mm away cannot reach a shared arbiter and its pick logic in one cycle.
  - Register requests before the pick. The placer may still put the register by the source, leaving the long wire after it; two stages split it.
  - Each stage costs 0.5–1.2% of kernel cycles (measured on the double-wide chip).
- **Pads next to cell-free bands.**
  - Pad nets more than about 2 mm from any legal cell site cannot be buffered; slew and capacitance fail.
  - Keep placeable rows near the pads, with power rails joined to the supply buses, and re-run the grid check after.
- **Antenna diodes count as fanout.** Long single-sink nets collect 10+ diodes and fail max fanout. Fix: buffer halfway along the net, then re-route from before detailed routing.
- **Congestion.**
  - A narrow central strip congested; widen it and use 2 sites of cell padding.
  - A 25% placement density target let one region reach 26% and global routing never converged; 18% routed.
- **PDN.**
  - Short the 1.8 V domains together where the harness allows it (Sky130 OpenFrame: vccd/vccd1/vccd2, vssd/vssd1/vssd2; keep vddio/vssio isolated).
  - Add vertical buses where the top metal runs one way only.
  - A band narrower than the stripe pitch is treated as a channel needing a strap (`PDN-0179`).

## Adapting to another PDK or fab program

Everything above carries over. Before the first run on a new PDK or fab program, settle these:

- **Corners:** the PDK's process/voltage/temperature corners and parasitic extraction corners; which are signoff and which is typical.
- **Cell library:** the simulation models and their delay defines, liberty per corner, physical-only cell names (for netlist stripping), antenna and tie cells.
- **Harness and pads:** the fab program's wrapper port list, pin template, supply-port method, pad models and their speed, and what the harness requires of supply domains.
- **Signoff tools:** the fab's own DRC/LVS decks and manufacturability checks, run in addition to the flow's.
- **Constraints:** the board-interface budget for I/O delays. Write it down and justify it, because at the typical corner it can set the clock.
- **Memory and server limits:** expected peak memory per step, and a guard that stops runaway steps before they take the server down.
- **Baseline:** re-run this document's evaluation on the previous chip with the new flow, to separate flow changes from design changes.
