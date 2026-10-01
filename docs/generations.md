# cf-openframe generations

Each generation of the OpenFrame chip, in all three formats, on the same benchmarks:
- every change is applied to SF16, FP16 and BF16 alike;
- only the formats' own datapath (PE, FMA and activation units) differs between them;
- each figure says how it was measured. The method is in `docs/evals.md` and `docs/gpt2_benchmark.md`.

## v1: signed off (2026-09-30)

Commits through `dae0cfe` (chips) and `0884a30` (benchmark), branch `cf-openframe`.

GPT-2 small, 32-token prompt and 32 generated tokens, each chip at its guaranteed peak clock (ss, 100 °C, 1.60 V). Async pin bus, ideal host.

| | SF16 | FP16 | BF16 |
|---|---|---|---|
| Peak clock, worst corner | 51.9 MHz | 55.7 MHz | 54.1 MHz |
| Peak clock, typical corner | 87.9 MHz | 88.8 MHz | 87.1 MHz |
| Tile standard-cell area (3.375 mm² macro) | **1.402 mm²** | 1.861 mm² | 1.634 mm² |
| Tile power, gate-level, decode, 50 MHz | **60.7 mW** | 113.0 mW | 108.0 mW |
| Chip power, decode, 50 MHz | **251.0 mW** | 459.7 mW | 440.6 mW |
| Cycles, decode token (context 33–63) | 1,104–1,108 M | same | same |
| Cycles, 32-token prefill | 7,281 M | same | same |
| Time to first token | 140.2 s | **130.8 s** | 134.5 s |
| Time per output token | 21.3 s | **19.9 s** | 20.4 s |
| Energy per decode token | **5.55 J** | 10.17 J | 9.74 J |
| Energy, 32 + 32 tokens | **209 J** | 382 J | 366 J |

## v2: in development

Branch `cf-openframe-v2`, from `6ea600e`. Not hardened yet. The figures below are RTL cycle counts through the pins with an ideal host, which answers a sync-bus read in the next cycle. Clock, power, area and the GPT-2 totals come with the hardening.

### Where v2 stands

One round of the four tiles (4 blocks, K = 768), SF16:

| Cycles | v1 timing, async bus | v2, async bus | v2, sync bus | v1 → v2 sync |
|---|---|---|---|---|
| Decode (gemv) | 210,851 | 140,826 | 27,998 | **7.5×** |
| Prefill (gemm, 8 tokens) | 445,296 | 254,542 | 41,869 | **10.6×** |

Per block, as the host schedules them (v1: launches of 10 and 9 blocks; v2: launches of 8):

| Cycles per block | v1 | v2, sync bus | v1 → v2 |
|---|---|---|---|
| Decode | 54,524 | 6,998 | **7.8×** |
| Prefill | 125,010 | 10,465 | **11.9×** |

- **Decode is at the pins.** The 16-bit bus is 91% busy, and a weight costs one beat. Going further means more bits per cycle (see the wide-read note below).
- **Prefill is not, yet.** The bus is 75% busy; each tile waits on its own two loads per k-step (61% of tile cycles).

### Formats

The latest step, launches of 8 blocks (two rounds), sync bus:

| Cycles | SF16 | FP16 | BF16 |
|---|---|---|---|
| Decode, gemv K = 768 | 55,981 | 56,009 | 56,009 |
| Prefill, gemm K = 768 | 83,723 | 83,723 | 83,723 |

The only difference: FP16 and BF16 `ACT` takes two cycles more than SF16, since the FP activation unit is pipelined through the scheduler's REQUEST and WAIT states. A decode block has 7 `ACT` (14 cycles a round); prefill has none. The cycle counts are otherwise identical, so the formats separate on clock, power and area.

### Changes

| Area | Change | Commit |
|---|---|---|
| ISA | `SH` (shift by a signed register amount) and `CONSTH` (load high byte: any constant in two instructions) | `9b445f2` |
| ISA | `SYS load.b`: one load puts the same weights in every row of the array | `b6d6c76` |
| Tile memory | A per-tile queue replaces the one-at-a-time arbiter: reads are taken ahead of their answers, answers return in order | `b5b90e4` |
| Pin bus, async | The next handshake starts in the cycle the previous one completes | `b5b90e4` |
| Pin bus, sync | New launch-selected mode: the host runs on the chip's clock, 8 reads in flight, answers in order, identical reads joined | `b5b90e4` |
| Pin bus, sync | A two-entry request buffer per tile; a tile keeps the bus while it has requests (sticky arbitration), so the tiles take turns | `5db8ce4` |
| Pin bus, sync | Eight lines of recent data answers: a tile reads a word another tile just read without a beat | `3fe36bb` |
| Core | A 32-entry instruction buffer per tile; only instructions that need REQUEST/WAIT pass through them | `5db8ce4`, `a98cca9` |
| Core | The next instruction is fetched during UPDATE: a single-cycle instruction takes 3 cycles instead of 5 | `3c0a57e` |
| Core | A load's request goes out in REQUEST; WAIT ends in the cycle of the last answer, and loads and stores skip EXECUTE | `c199480`, `2d84c76` |
| Core | A `SYS read` waits in DECODE only while the last compute is in flight; FP16/BF16 reads no longer pass through REQUEST/WAIT | `dcc2f57` |
| Host | Launches of 8 blocks (decode and prefill) and 28 (attention): no tile idles in a launch's last round | `5294e09` |
| Branch divergence | Kept off: the unit gates nothing and the kernels do not diverge | — |

### Step log

The same two launches at every committed step: decode is gemv, prefill is gemm, each 4 blocks of K = 768 (one round of the four tiles). SF16, ideal host. Every run's outputs match the bit-exact reference. A dash marks a run not made.

| Step | Commit | Decode, async | Decode, sync | Prefill, async | Prefill, sync |
|---|---|---|---|---|---|
| v1 timing, with `SH` and `CONSTH` | `9b445f2` | 210,851 | — | 445,296 | — |
| Tile queue, trimmed async handshake, sync bus | `b5b90e4` | 160,629 | 59,099 | 342,465 | 162,980 |
| Instruction buffer, REQUEST/WAIT skip, bus request buffers, sticky arbitration | `5db8ce4` | — | 31,733 | — | 86,945 |
| FMA, FP ACT and FP SYS read keep REQUEST/WAIT (fix, see notes) | `a98cca9` | — | 31,733 | — | 86,945 |
| Broadcast SYS load in gemm | `b6d6c76` | — | 31,733 | — | 61,995 |
| Shared-read lines | `3fe36bb` | 147,872 | 31,442 | 265,257 | 55,839 |
| Fetch ahead | `3c0a57e` | — | 28,594 | — | 45,912 |
| Load request in REQUEST | `c199480` | — | 28,391 | — | 44,366 |
| Load turnaround | `2d84c76` | 140,826 | 27,998 | 254,542 | 41,869 |
| SYS read interlock (SF16 unchanged; FP16/BF16 see Formats) | `dcc2f57` | — | 27,998 | — | 41,869 |

Launch size, measured at `b6d6c76` (SF16, sync, cycles per block):

| | Launch of 10 (decode) or 9 (prefill) blocks | Launch of 8 blocks |
|---|---|---|
| Decode | 9,468 | 7,931 |
| Prefill | 19,926 | 15,497 |

### Notes

- **A bug the skip introduced, and the test that missed it.** `5db8ce4` sent every instruction but loads and stores from DECODE straight to EXECUTE. The FMA units (all formats) and the FP16/BF16 activation unit register their pipeline stages at the end of REQUEST and WAIT, so FMA was wrong in every format and FP16/BF16 `ACT` too. `a98cca9` gives them those cycles back.
  - The tile-level FMA/ACT test ran in FP16 and BF16 only, and no kernel used FMA. It now runs in SF16 as well, against `helpers/q115.py`, and fails without the fix (209 of 1,280 results wrong).
  - With instructions as short as three cycles (`3c0a57e`), a `SYS read` right after a `SYS compute` sampled the accumulators early: a cycle early in SF16, three in FP16/BF16. The kernels never do this, so no regression showed it. `dcc2f57` holds such a read in DECODE, and a tile test (compute, compute, read, back to back) fails without it in every format.
- **Sticky arbitration and shared reads.** Round-robin lets tiles in step join each other's reads, but they then load at the same time and compute at the same time: the bus is half idle. Sticky arbitration staggers them, which overlaps one tile's loads with another's compute, but no two tiles then read a word at the same moment. The shared-read lines keep the answers long enough for the next tiles: prefill bus reads fell 37% (98,496 to 61,632 for 8 blocks).
- **Wide reads (evaluated, not built).** All 44 GPIOs are in use, and decode takes 10% more cycles than it has bus reads. The options:
  - double data rate on `bus_in`: 100 Mbit/s per pad at 50 MHz, beyond what the sky130 GPIO pads can be relied on for;
  - turning `bus_out` around for bursts, 32 input bits per cycle: an 8-word burst (one `LDR`) gains 1.14× after the address beat and two turnarounds; 64-word bursts into the tile scratchpad would reach about 1.8×, but need a DMA instruction, dynamic pad direction in the wrapper and a new host protocol;
  - two 8-bit weights per word: changes the numerics.

  All three help every format equally. The burst DMA is the candidate for a later generation.
- **Loads that do not block (analysed, not built).** Prefill tiles spend 61% of their cycles waiting on two loads per k-step. With one LSU per thread, and SYS operands fixed to R0 and R1, a non-blocking load only overlaps the two pointer adds, about 10%. Overlapping the activation and weight loads needs two loads in flight per thread (a second LSU per thread, or a paired `LDR`). That is an ISA and area decision, estimated at up to 1.4× on prefill, where the bus then limits.
- **For the v2 hardening.** v1's SF16 tile was limited by a wire path (11 of 37 stages repair buffers), not by its arithmetic, because its cells fill 42% of the macro all three formats share (FP16's fill 55%). Each format's tile macro should be sized by one shared rule, the same target utilization for all three.
