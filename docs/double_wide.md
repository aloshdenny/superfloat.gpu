# Atreides on ChipFoundry Double-Wide OpenFrame: plan

This document plans the `cf-dw-openframe` build of the Atreides GPU for ChipFoundry's double-wide OpenFrame harness on SKY130. It starts from the `cf-openframe` design (see `docs/openframe.md`): the same core tile, number formats, pin-bus protocol and hardening flow. It records the target's specifications, the measurements that decide how to use the extra area, the recommended architecture, the physical and flow plan, and the order of work.

The SF16 double-wide chip enters hardening once the three single-wide OpenFrame chips (SF16, FP16, BF16) are signed off. Work that needs no hardening server time (RTL, simulation, floorplan scripts) can proceed before then.

## Target

Taken from ChipFoundry's harness repository, [chipfoundry/double_wide_openframe](https://github.com/chipfoundry/double_wide_openframe) (`docs/datasheet.md`, `verilog/rtl/`, `librelane/wrapper/`), as of 2026-08-03:

| | OpenFrame (`cf-openframe`) | Double-wide OpenFrame |
|---|---|---|
| Die | 3588 × 5188 µm (18.6 mm²) | 7176 × 5188 µm (37.2 mm²) |
| User area (wrapper) | 3166.63 × 4766.63 µm (15.1 mm²) | 6754.63 × 4766.63 µm (32.2 mm²) |
| Core area at a 40 µm inset | 14.5 mm² | 31.3 mm² |
| GPIOs | 44 | 63 (`gpio[62:0]`) |
| Wrapper module | `openframe_project_wrapper` | `double_wide_openframe_project_wrapper` |
| Wrapper pins (template) | 877 signal pins | 1216 pins |
| Reset inputs | `resetb_h/l`, `porb_h/l`, `por_l` | same |
| Core supply into the wrapper | `vccd1_connection` / `vssd1_connection` macros | met3 edge ports aligned to the pad-ring clamps, from the pin template |
| `vccd1` / `vssd1` bond pads | 1 / 1, east edge | 1 / 1, east edge |
| `vccd2` / `vssd2` bond pads | west edge | 1 / 1, west edge |

The west and east pad columns are the OpenFrame ones; the north and south rows are the OpenFrame rows side by side, plus two pads at the seam of each.

**Template versions.** The user-project template ([chipfoundry/dw_openframe_user_project](https://github.com/chipfoundry/dw_openframe_user_project), 2026-07-16) still has the earlier 59-GPIO wrapper (`[58:0]`, 1003-pin template). The harness is the reference: its wrapper and `librelane/wrapper/pin_template.def` are 63-GPIO, and the harness README says the user project must match them. This build takes the wrapper ports and pin template from the harness.

## What carries over from `cf-openframe`

- The core tile as signed off: lean SF16 PE, 4-stage FP16/BF16 PE, 8 threads, 8 × 8 array, 1500 × 2250 µm macro. Its pins face the horizontal centre strip, which suits a longer strip.
- Tile timing models with hold arcs (`core_tile/timing_model.sh`), so the chip times hold into every tile.
- The chip flow settings: repair against the tighter `pnr.sdc`, 500 µm repeaters, 25% glue density, well taps at every row end, Magic DRC and extraction from GDS with the tiles abstract, diode antenna repair after routing with ten passes.
- A clock buffer at each tile clock pin right after CTS, before hold repair.
- `eco_fix.py` for residual slew, capacitance, and diode-induced fanout.
- The pin-bus protocol and IO constraints (multicycle data pins, synchronised handshake), unless the bus is redesigned (see below).

## Measurements that decide the design

### Where the tile's area goes

Synthesised with the same Yosys script for each block (sky130_fd_sc_hd, tt corner, flattened, no placement):

| Block | SF16 | FP16 | BF16 |
|---|---|---|---|
| 8 × 8 systolic array | 0.161 mm² | 0.196 mm² | 0.159 mm² |
| Whole core tile | 1.003 mm² | 1.168 mm² | 0.999 mm² |
| Array share of the tile | 16% | 17% | 16% |
| Whole tile with a 16 × 16 array and 16 threads | 3.541 mm² (3.5×) | | |

The array is a small part of the tile. Most of the area is the eight threads that feed it (each with an ALU, FMA, activation unit, LSU and register file), the per-thread result muxes and the scratchpad. Under the current ISA, thread *i* supplies row *i* of the array, so a larger array needs proportionally more threads.

A 16 × 16 tile gives 4× the MACs for 3.5× the area: 72 MACs per synthesised mm² against 64 today.

After placement, routing and repair, the signed-off SF16 tile occupies 3.375 mm² at 0.42 utilisation.

### The pin bus limits throughput

RTL simulation of the SF16 chip with the cocotb host model, run with 1, 2, 4 and 8 tiles. The 8-tile build needed no RTL changes beyond the test wrapper. "Ideal" replaces the pin bus with one-cycle memory per tile:

| Kernel | 4 tiles (cycles) | 8 tiles (cycles) | 4 → 8 speedup | Same step, ideal memory |
|---|---|---|---|---|
| Systolic 8 × 8, 8 blocks | 16,176 | 14,239 | 1.14× | 2.00× |
| FMA + 4 activations, 64 threads | 41,994 | 40,737 | 1.03× | 1.99× |
| 12 × 12 FMA matmul, 144 threads | 31,341 | 29,209 | 1.07× | 1.66× |

These use the fastest host response the model allows. With 8 tiles the bus is busy 89–99% of cycles, and tiles spend 83–93% of their active time waiting on memory. The causes, all measured:

- **Per-transaction cost.** A read costs 7 cycles and a write 10 (two-phase handshake, synchroniser on `bus_ack`, registered outputs). At 50 MHz that is at most 7.1 M reads/s. Every extra cycle of host latency adds exactly one cycle per beat.
- **One channel per tile.** Each tile's arbiter merges its 8 LSUs onto one memory port. Even with ideal memory, a systolic tile waits on memory 46% of the time.
- **Instruction cache.** The 118-instruction systolic kernel does not fit the 32-entry shared instruction cache, so a lone tile re-reads the program for every block (32% of its beats).

**Conclusion.** Doubling the tiles on the current bus buys 3–14%. The extra area pays off only if memory bandwidth rises with it.

## Scaling options

| | Tiles × array | MACs | Threads | Fits 31.3 mm² | Expected gain over the 4-tile chip |
|---|---|---|---|---|---|
| A | 8 × (8 × 8), tile reused as signed off | 512 | 64 | yes: 27 mm² of tiles, 0.5 mm strip spare | 1.03–1.14× on the current bus; up to 1.7–2.0× with enough bandwidth |
| B | 4 × (16 × 16), 16 threads per tile, new tile harden | 1024 | 64 | no: 9–12 mm² per tile at 0.55–0.42 utilisation, so 36–48 mm². Three fit only at ≥ 0.55 (768 MACs) | bandwidth-bound in the same way |
| C | 8 × (8 × 8) plus a faster memory system | 512 | 64 | yes, with the spare strip and denser tiles | the ideal-memory column, less what the new bus cannot supply |

## Recommendation

**Build option C in two steps, and decide the host interface first.**

1. **The same tile, twice as many.** Reuse the signed-off SF16 tile unchanged: no tile re-harden, and it is already closed and timing-modelled. Place 8 of them in a 4 × 2 grid.
2. **Raise memory bandwidth, which is where the gain is.** In order of gain per effort:
   - **Synchronous burst pin bus.** If the benchmark host supplies the chip clock (it already drives `clk` on a GPIO), the host is synchronous with the chip and the synchronisers can go. Then one beat per cycle instead of one per 7 to 10. Use the 19 extra GPIOs for a 32-bit read path. The combination is up to about 14× the read bandwidth of the current bus.
   - **Larger shared instruction cache** (32 → 128 entries), so looping kernels stop re-reading the program.
   - **Wider tile memory port or a second channel per tile.** This touches the tile, so it means a tile re-harden; take it only if simulation shows the pins are no longer the limit.
   - **On-chip data SRAM** (sky130 OpenRAM or ChipFoundry SRAM macros) in the spare strip, holding weights reused across blocks. Size and placement to be decided once the bus change is measured.
3. **Larger arrays later, and only with an ISA change** that decouples array rows from threads, for example a vector load into a whole array row. Under the current ISA a larger array costs threads, which is most of the tile area. A 16 × 16 tile is only 13% denser in MACs, cannot fit four to a chip, and needs a new tile harden.

Every step is simulated against the current cycle counts before it goes to the server, and nothing is hardened until simulation shows the gain.

**Decisions needed from you:**
- **Benchmark host.** What drives the chip: an FPGA, a microcontroller, or the ChipFoundry board? A synchronous burst bus needs a host that can run at the chip clock.
- **Supply pads.** Whether the west half may run from `vccd2`/`vssd2` (see Power). This needs ChipFoundry's confirmation.
- **Scope.** SF16 first, as planned. FP16/BF16 double-wide chips, if wanted, follow the same path with their own tiles.

## Physical plan

- **Floorplan.** Tiles at x = 60, 1606.63, 3153.26 and 4699.89 µm, in two rows at y = 70 (N/FN) and 2446.63 (FS/S), as in the single-wide chip. That leaves the centre strip (y 2320–2446.63) 6.1 mm long for the top-level logic, and a 0.5 mm × 4.7 mm band on the east side for the bus, instruction cache or SRAM.
- **Pins.** The harness pin template, extended 3 µm inward with `extend_pins.py`, which is generalised for the new wrapper. The GPIO map is redone for 63 pins: clock, bus, handshake, status, and one `core_active` per tile or a status summary.
- **Power.** The whole core draws through one `vccd1` and one `vssd1` pad on the east edge.
  - STA puts the signed-off tile at 64.4 mW (nom_tt, default switching activity), which is about 0.27 W for today's 4-tile chip and about 0.55 W for 8 tiles before data activity, around 300 mA at 1.8 V.
  - Before committing, measure power with realistic activity (the benchmark workloads), get the pad current rating, and check IR drop across the 6.7 mm width. The DW edge ports, unlike the connection macros, may let OpenROAD's IR-drop analysis run.
  - If one pad is not enough, the west tiles can take `vccd2`/`vssd2`. ChipFoundry's datasheet recommends `vccd1`/`vssd1` for digital logic, so this needs their agreement.
- **Clock.** One tree spanning about 6.1 mm with 8 tile sinks. Keep the per-tile clock buffers and hold repair against the tile timing models.

## Flow and infrastructure

- **Hardening server memory.** The WSL VM has 30.8 GB of the host's 61.6 GB. The single-wide chip's signoff already peaks at 22 GiB (Magic WriteLEF), with Magic DRC and extraction at 8–9 GiB each. The double-wide chip is expected to need roughly twice that. Raising the WSL limit (`memory=` in `.wslconfig`) requires `wsl --shutdown`, which stops every running job. Do it between runs, with your approval.
- **Runtimes to expect**, scaled from the single-wide chip's measured times: Magic DRC about 2 h (single-wide: 1 h 03 min), KLayout DRC about 1 h (23 min), extraction 2 h or more. Chip placement and routing stays well under an hour.
- **ChipFoundry flow differences.** The harness hardens its empty wrapper with LibreLane 3 and its own PDN script. The user-project template turns DRC off and reports open LVS mismatches for its sparse example. Our flow keeps full Magic/KLayout DRC and LVS, as on `cf-openframe`.

## Order of work

| Phase | Work | Server | Starts |
|---|---|---|---|
| 0 | Vendor the harness wrapper, pin template and power-port method; parameterise the top level and test wrapper for 8 tiles and 63 GPIOs | no | now |
| 1 | Pin-bus and instruction-cache redesign in RTL; cycle-accurate comparison against the tables above | no | after the host decision |
| 2 | Chip floorplan and PDN on the DW wrapper with 8 SF16 tile views; a trial PnR to STA | light | when the server is free |
| 3 | Full SF16 DW harden, ECO, signoff (DRC, LVS, timing in all corners) | heavy | after the three OpenFrame chips are signed off |
| 4 | Optional: FP16/BF16 DW chips, tile changes, SRAM | heavy | after phase 3 |

## Risks

- **Bandwidth.** More tiles without a faster memory system do not pay off (measured above).
- **Power delivery.** A single core-supply pad pair for about 32 mm² of logic.
- **Server memory.** Chip signoff steps may not fit in 30.8 GB.
- **Harness maturity.** The harness is recent (2026-08). The user-project template lags it, and its example flow runs without DRC. Our own signoff must stay complete, and the integration step (`make integrate` in the harness) should be tried early.
- **Long top-level wires.** Strip nets and pad routes about 6 mm long need repeaters within the 500 µm rule, and the extended pins, as on the single-wide chip.
