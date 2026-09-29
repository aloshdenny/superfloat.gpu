# Atreides on ChipFoundry OpenFrame

This document covers the `cf-openframe` build of the Atreides GPU for the ChipFoundry OpenFrame harness on SKY130: the architecture, the number formats, the floorplan, the pin map, the memory bus protocol a host must implement, and how to simulate and harden the design. The Tiny Tapeout build on `main` is separate and unaffected.

## Architecture

| Item | Value |
|---|---|
| Compute tiles | 4 |
| Threads per tile (block size) | 8 |
| Systolic array per tile | 8 × 8, weight-stationary |
| Number format | SF16, FP16 or BF16, fixed per chip (see below) |
| MAC units | 256 |
| Target clock | 50 MHz (20 ns) |
| Program memory (host side) | 512 × 16-bit instructions |
| Data memory (host side) | 64 K × 16-bit words |
| On-die scratchpad | 128 B per tile at 0xFFC0–0xFFFF, private to the tile |

Each **core tile** (`src/core_tile.sv`) is one hardened macro. It contains:
- one core (fetcher, scheduler, and 8 threads, each with its own ALU, FMA, activation unit, LSU, register file and PC)
- the 8 × 8 systolic array
- the instruction decoder
- the private scratchpad
- an arbiter that merges the 8 LSUs into a single data-memory port

The top level (`src/superfloat_openframe.sv`) holds only the block dispatcher, the device control register, a launch sequencer and the pin bus (`src/openframe_bus.sv`).

### Number formats

The same chip is built in three variants that differ only inside the core tile. The `NUMBER_FORMAT` parameter selects the variant, from `superfloat_openframe` down to the PEs: 0 = SF16, 1 = FP16, 2 = BF16. The ALU, the addressing, the pin bus and the ISA are the same in all three; FMA, ACT and the systolic array change arithmetic.

| | SF16 | FP16 | BF16 |
|---|---|---|---|
| Encoding | Q1.15 sign-magnitude | IEEE binary16 (1/5/10) | bfloat16 (1/8/7) |
| Range | (−1, 1) | ±65504 | ±3.4 × 10³⁸ |
| Multiply-accumulate | 15 × 15 product truncated to Q1.15, saturating add | fused `round(a × b + acc)` | fused `round(a × b + acc)` |
| Systolic accumulator | 16-bit two's complement, saturating | FP16 | BF16 |
| PE pipeline | 3 stages | 4 stages (multiply, align+add, round) | 4 stages |

FP16 and BF16 arithmetic (`src/fp_arith.sv`):
- Every multiply-accumulate rounds the exact `a × b + c` once, to nearest with ties to even.
- Subnormal inputs read as zero, and a result below the smallest normal becomes a signed zero (flush to zero, tininess before rounding). Overflow gives infinity.
- A NaN input, `inf × 0` or `inf − inf` gives the quiet NaN `0x7E00` (FP16) or `0x7FC0` (BF16).
- Zero signs follow IEEE 754: an exact zero sum of non-zero terms is +0, and `0 + 0` is −0 only when both are −0.
- ACT computes `f(round(x + bias))`. ReLU maps negatives, including −0, to +0. Leaky ReLU multiplies negatives by 2⁻⁷ exactly, flushing to −0 below the smallest normal. Clipped ReLU is `min(1.0, ReLU)` and keeps NaN.
- `test/helpers/fp16fmt.py` is the bit-exact reference for all of the above.

Every kernel runs in the same number of cycles in all three formats. The FP PE's accumulator loop (align+add, round) takes two cycles, and its extra pipeline depth is hidden, since two SYS instructions are always at least six cycles apart.

### Programming notes

- **Thread indices:** `%threadIdx` runs 0–7 and `%blockDim` is 8. A launch of *N* threads is split into ⌈N/8⌉ blocks, dispatched to free tiles in order. The last block may be partial; its disabled threads do not execute stores.
- **Systolic array:** thread *i* supplies row *i* of the activation stream through R0 and column *i* of the weights through R1.
  - `SYS load` shifts the weight rows in from the top, so load rows 7, 6, …, 0.
  - Each `SYS compute` accumulates `R0 × weight` into every PE of the row. Column 0 uses the current operand; columns 1–7 use the previous one. Issue one extra `SYS compute` with R0 = 0 at the end.
  - `SYS read Rd` returns the cell selected by `R0[5:0]` (row × 8 + column).
  - `test/test_openframe_tile.py` contains a complete kernel and a bit-exact reference model.
- **Scratchpad:** loads and stores to 0xFFC0–0xFFFF stay in the tile and never reach the pins. Each tile has its own copy, so the scratchpad is for data shared among the threads of one block.

## Floorplan

The user area is the OpenFrame wrapper, 3166.63 × 4766.63 µm (15.09 mm²). The core area is inset 40 µm on every side for the power ring, which leaves 14.47 mm².

| Instance | Origin (µm) | Orientation |
|---|---|---|
| `tiles[0]` | (60, 70) | N |
| `tiles[1]` | (1606.63, 70) | FN |
| `tiles[2]` | (60, 2446.63) | FS |
| `tiles[3]` | (1606.63, 2446.63) | S |

- **Tile size:** 1500 × 2250 µm.
- **Pins:** every tile's pins sit on the edge facing the horizontal centre strip (y 2320–2446.63 µm). The top-level logic is placed in that strip.
- **Power:** vccd1 and vssd1 enter on the east edge through ChipFoundry's `vccd1_connection` and `vssd1_connection` macros.
- **Power grid:** met4 vertical and met5 horizontal straps at a 180 µm pitch with a 20 µm core ring. Each tile's met4 grid connects to the chip's met5 straps.

## Pin map

| GPIO | Edge | Dir | Signal |
|---|---|---|---|
| 0–14 | east | out | `bus_out[14:0]` |
| 15 | north | out | `bus_out[15]` |
| 16 | north | out | `bus_sel`: 0 = program memory, 1 = data memory |
| 17 | north | out | `bus_we` |
| 18 | north | out | `bus_beat`: 0 = address beat, 1 = write-data beat |
| 19 | north | out | `bus_req` |
| 20 | north | in, pull-down | `bus_ack` |
| 21 | north | in, pull-down | `start` |
| 22 | north | out | `done` |
| 23 | north | out | `core_active[0]` |
| 24–37 | west | in | `bus_in[13:0]` |
| 38 | south | in | `clk` (the Caravel board oscillator pin) |
| 39–40 | south | in | `bus_in[15:14]` |
| 41–43 | south | out | `core_active[3:1]` |

The chip is held in reset while either the `resetb` pad or the power-on reset is asserted. `core_active[i]` is high while tile *i* is running a block.

## Memory bus protocol

The chip is the bus master. The host holds program memory and data memory and answers one transaction at a time.

- **Handshake:** two-phase. The chip toggles `bus_req` for each beat. The host completes the beat by setting `bus_ack` equal to `bus_req`.
- **Clocking:** `bus_ack` passes through a two-flop synchronizer, so the host does not need to share the chip's clock.
- **Output timing:** all chip outputs are registered and settle one cycle before `bus_req` toggles.

**Read** (one beat):
1. The chip drives `bus_out` = address, `bus_sel`, `bus_we` = 0, `bus_beat` = 0, then toggles `bus_req`.
2. The host drives the word on `bus_in`, then sets `bus_ack` = `bus_req`.

**Write** (two beats):
1. Address beat: `bus_out` = address, `bus_we` = 1, `bus_beat` = 0, toggle `bus_req`. The host latches the address and acknowledges.
2. Data beat: `bus_out` = data, `bus_beat` = 1, toggle `bus_req`. The host writes the word and acknowledges.

**Host rules:**
- Synchronise `bus_req` into the host's clock domain (two flops) before acting on a toggle, and read `bus_out`, `bus_sel`, `bus_we` and `bus_beat` only after that. The chip's timing constraints guarantee those outputs within two chip cycles of their register edge, which is one cycle before `bus_req` toggles; the synchroniser covers the rest.
- `done` and `core_active` are status signals with no timing relation to the host clock; synchronise them too.
- After reset `bus_req` is 0, and the host must hold `bus_ack` at 0.
- `bus_in` must be stable before the host changes `bus_ack`, and must stay stable until `bus_req` toggles again.
- Program memory is never written.
- Program addresses are 9 bits, zero-extended on `bus_out`.

## Launching a kernel

1. Load program and data memory on the host side.
2. Drive the thread count on `bus_in[7:0]` and raise `start`.
3. The chip latches the thread count, resets the compute array, writes the count and begins fetching. `done` rises when every block has finished.
4. Lower `start`. `done` falls, and the chip is ready for the next launch without a chip reset.

`test/test_openframe_chip.py` contains a host model that implements this sequence, with a randomized response delay.

## Simulation

Every target below takes `NUMBER_FORMAT=0|1|2` (default 0, SF16) and checks results against the model of that format.

```bash
make test_openframe_tile NUMBER_FORMAT=1
```

Runs at the GPU level with ideal memory. It checks an 8 × 8 systolic matmul on all four tiles bit-exactly, and that each tile's scratchpad is private.

```bash
make test_openframe_chip NUMBER_FORMAT=1
```

Drives the chip-level digital top through its pins. It runs two kernels back to back and a partial launch.

```bash
make test_openframe_fp NUMBER_FORMAT=1
```

FP16/BF16 only:
- FMA and all four ACT functions on 256 vectors that mix normal values, signed zeros, infinities, NaN, values near overflow and near the smallest normal, and cancelling operands.
- The systolic kernel on the same kinds of operands.

Results must match `test/helpers/fp16fmt.py` bit for bit.

```bash
make test_fp_arith
```

Checks the fused multiply-add datapath on its own against the reference model: 1 M vectors per format (FP16 and BF16).

The existing instruction-level suites (`make test_matadd`, `make test_matmul`, `make test_matmul_large` and others) run on the same 4-tile configuration through `test/tb_gpu.sv`.

## Hardening

Both steps use LibreLane in its nix shell. `run_harden.sh` finds the `librelane` checkout next to this repository, or takes its path from `$LIBRELANE`. Run each harden in a detached `tmux` or `screen` session; a harden takes hours. The log ends with `HARDEN_EXIT <code>`.

| Format | Tile config | Tile views | Chip config |
|---|---|---|---|
| SF16 | `core_tile/config.json` | `core_tile/views/` | `openframe/config.json` |
| FP16 | `core_tile/config_fp16.json` | `core_tile/views_fp16/` | `openframe/config_fp16.json` |
| BF16 | `core_tile/config_bf16.json` | `core_tile/views_bf16/` | `openframe/config_bf16.json` |

The FP16 and BF16 configs are generated from the SF16 ones by `librelane/make_variants.py`; rerun it after editing an SF16 config.

1. **Core tile:** in `librelane/core_tile/`, run `./run_harden.sh config_fp16.json harden_fp16.log`.
   - If signoff reports residual max-slew or max-cap violations, `./eco_fix.py runs/<run> --config config_fp16.json` writes an ECO config. It buffers the violating drivers from the routed state and re-runs signoff, and prints the command to run it.
   - `./export_views.sh runs/<signed-off run> views_fp16` copies the views the chip uses.
2. **Chip:** in `librelane/openframe/`, run `./run_harden.sh config_fp16.json harden_fp16.log`.
   - The top design is `openframe_project_wrapper`. The four tiles are placed as macros, and the define `CORE_TILE_MACRO` makes `gpu.sv` instantiate them without parameter overrides.
   - Chip timing uses the tiles' signed-off `.lib` views.
   - **Pin template:** the chip starts from `openframe/pins_extended.def`, not from ChipFoundry's fixed DEF directly.
     - The fixed pins reach only 0.3 µm into the die, so the detailed router cannot place access points on them (DRT-1231).
     - `extend_pins.py` derives the copy with every signal pin extended 3 µm inward. Nothing outside the die boundary changes, and that band is what precheck compares with the empty wrapper.
   - **Chip-level repair settings:**
     - Repair works against `pnr.sdc` (1.0 ns max transition, fanout 8); signoff uses `chip.sdc` (1.5 ns, fanout 10). The margin covers the difference between pre-route estimates and routed parasitics on the ~1 mm strip nets, and the antenna diodes added after routing.
     - Repeaters are inserted only on nets over 1000 µm, which are the strip-to-pad nets. A 200 µm limit filled the 46 µm channel between the tile columns.
     - Timing repair aims for 0.6 ns of setup slack, and glue logic is placed at 25% target density. All four tiles' pins meet at the chip centre; at 35% density with a 1 ns margin, repair crowded that area until detailed routing left met5 shorts over the tiles.
     - The dispatcher registers the block count and the last block's thread count, so its per-core dispatch chain stays short. Without this it was the longest top-level path, about 19 ns at max_ss. A launch takes one extra cycle.
     - Clock sinks are clustered by 8, clock wires are buffered every 400 µm, and clock buffers drive at most 0.3 pF.
     - The pad-only `analog_*` and `gpio_loopback_*` nets are don't-touch.
     - Legalization may move a cell up to 1000 × 1500 µm, so slew buffers that repair drops over a tile reach a legal row.
     - Each row segment ends in a well-tap cell (`ENDCAP_CELL` is `tapvpwrvgnd_1`). The 13 µm tap grid alone left the 9.7 µm segments beside the tiles untapped, and a 4 µm grid split the strip rows too finely to place larger cells.
   - **Pad configuration** constants come from tie cells, not from the pads' `gpio_loopback_*` pins (see `src/openframe_project_wrapper.v`).
   - **Supply pins:**
     - vccd1 and vssd1 reach the core ring through ChipFoundry's `vccd1_connection`/`vssd1_connection` macros. Their LEF is only an obstruction, so OpenROAD's IR-drop analysis cannot see the connection and is off.
     - Magic extracts from GDS with the tiles abstract, so LVS checks the real connection.
     - Top-level port names are not uniquified in extraction, because the padframe joins the separate shapes of each unused supply pin (vddio, vccd2, ...).
   - **Magic DRC** runs on the GDS. Abstract-view DRC would flag the tile LEF's n-well and the supply macros' obstruction.

The ChipFoundry template files the chip harden depends on are vendored, unmodified, in `openframe/` (see `openframe/UPSTREAM.md`).
