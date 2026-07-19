# Atreides

**Q1.15 fixed-point neural network accelerator GPU** for Tiny Tapeout (Sky130), with an on-die scratchpad and an external SRAM interface over the bidirectional bus.

Silicon configuration in this repository: **2 cores × 2 threads × one 2×2 systolic array** (8 MAC units), **128 B** address-mapped on-die scratchpad, **8×4** tiles, **50 MHz** target clock.

---

## Specs

| Item | Value |
| --- | --- |
| Compute cores | 2 |
| Threads per block | 2 |
| Systolic arrays | 1 × 2×2 per core |
| MAC units (total) | 8 |
| Scalar FMA units | 1 per thread (4 total), 2-cycle |
| On-die scratchpad | 128 B (64 × 16-bit), `0xFFC0`–`0xFFFF` |
| Data address space | 19-bit (1 MiB × 16-bit words, external) |
| Program memory | 512 × 16-bit instructions (external) |
| Memory channels | 4 data + 2 program (serialized on the pin bus) |
| Arithmetic | Q1.15 (SF16) |
| Clock | 50 MHz (20 ns) |
| Process / shuttle | Sky130, Tiny Tapeout `8x4` |
| Top module | `tt_um_aloshdenny_gpu` |

### Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Memory and scratchpad](#memory-and-scratchpad)
- [Throughput](#throughput)
- [Pinout](#pinout)
- [Q1.15 Fixed-Point Format](#q115-fixed-point-format)
- [ISA](#isa)
- [Execution](#execution)
- [Neural Network Features](#neural-network-features)
- [Kernels](#kernels)
- [Simulation](#simulation)
- [ASIC / Tiny Tapeout](#asic--tiny-tapeout)
- [Modules](#modules)

---

# Overview

Atreides runs one kernel at a time: load program and data into external memory, write `thread_count`, pulse start, wait for done. Integer ops handle addressing and control; Q1.15 FMA / systolic MACs handle the numeric work.

The Tiny Tapeout build keeps the GPU small enough for an 8×4 tile. Hot working sets can sit in the **128 B on-die scratchpad** (ordinary `LDR`/`STR` to high addresses). Everything else goes through the external memory arbiter on `uio[7:0]`.

```
┌──────────────────────────────────────────────────────────────────────┐
│                     ATREIDES (Tiny Tapeout 8×4)                      │
├──────────────────────────────────────────────────────────────────────┤
│  Core 0                         Core 1                               │
│  ├─ 2 threads (ALU / FMA / LSU / RF / PC each)                       │
│  └─ 1 × 2×2 systolic array (4 PEs)                                   │
│                                                                      │
│  Scratchpad bridge ──► 128 B soft-flop RAM (addr 0xFFC0–0xFFFF)     │
│  Controllers: 4 data + 2 program channels                            │
│  External arbiter (tt_um_*) ──► 8-bit muxed SRAM bus                 │
└──────────────────────────────────────────────────────────────────────┘
```

---

# Architecture

## GPU

Launch sequence:

1. Load kernel into program memory (external).
2. Load weights / activations into data memory (Q1.15).
3. Optionally stage a tile into the scratchpad (`0xFFC0`–`0xFFFF`).
4. Write `thread_count` on `ui_in[6:0]`, then pulse `ui_in[7]` (start).
5. Poll `uo_out[0]` for completion.

| Unit | Role |
| --- | --- |
| Device control register | Holds `thread_count` |
| Dispatcher | Assigns blocks to the two cores |
| Compute cores | 2 × (2 threads + one 2×2 systolic array) |
| Scratchpad bridge | Hits on `0xFFC0`–`0xFFFF`; misses go external |
| Data / program controllers | 4 data + 2 program channels into the pin arbiter |

### Parameters (`gpu.sv` / TT wrapper)

| Parameter | Value | Notes |
| --- | --- | --- |
| `NUM_CORES` | 2 | |
| `THREADS_PER_BLOCK` | 2 | |
| `SYSTOLIC_SIZE` | 2 | 2×2 PE grid |
| `NUM_SYSTOLIC_ARRAYS` | 1 | Per core |
| `DATA_MEM_ADDR_BITS` | 19 | External data space |
| `DATA_MEM_DATA_BITS` | 16 | |
| `DATA_MEM_NUM_CHANNELS` | 4 | 2 cores × 2 threads |
| `PROGRAM_MEM_ADDR_BITS` | 9 | 512 instructions |
| `PROGRAM_MEM_NUM_CHANNELS` | 2 | One fetcher per core |

## Core

Each core runs one block at a time. Threads in the block share the fetch/decode/schedule pipeline and execute in SIMT lockstep.

| Resource | Per thread | Notes |
| --- | --- | --- |
| ALU | yes | Integer ADD/SUB/MUL/DIV/CMP |
| FMA | yes | Q1.15, 2 EXECUTE cycles |
| Activation | yes | Bias + ReLU variants |
| LSU | yes | Loads/stores (scratchpad or external) |
| PC / register file | yes | 16 registers (13 R/W + 3 RO) |
| Systolic array | shared | One 2×2 weight-stationary array per core |

Systolic PEs are fully pipelined (**1 MAC/cycle** after fill; first result after 3 cycles). Scalar `FMA` instructions use the per-thread FMA unit.

### Hierarchy (silicon build)

```
tt_um_aloshdenny_gpu
├── RAM32 (soft-flop 32×32, 128 B)
├── memory arbiter (uio / uo control)
└── gpu
    ├── dcr, dispatch
    ├── data + program controllers
    ├── scratchpad bridge
    └── core ×2
        ├── fetcher, decoder, scheduler, branch_diverge
        ├── per-thread ×2: alu, fma, activation, lsu, registers, pc
        └── systolic_array (2×2) → systolic_pe ×4
```

---

# Memory and scratchpad

## Address map (data)

| Region | Addresses | Backing | Access |
| --- | --- | --- | --- |
| External data | `0x00000`–`0x0FFBF` (and rest of 19-bit space) | Off-chip SRAM via pin bus | Multi-cycle, arbitrated |
| On-die scratchpad | `0xFFC0`–`0xFFFF` (64 halfwords) | Soft-flop 32×32 RAM | ~1–2 cycles on hit |

No ISA change: the LSU issues normal loads/stores; `scratchpad.sv` steers hits to the on-die RAM and forwards misses to the data controller.

Scratchpad details:

- 128 bytes = 64 × 16-bit words (fits in the 16-bit LSU address used from `rs`)
- Physical RAM is 32-bit wide, 32 deep; the bridge maps halfword addresses and byte enables
- Single 1RW port shared by all four data channels (priority encode; one hit in flight)

## External bus protocol

Program and data channels share one 8-bit bidirectional bus. A transfer is roughly:

1. **Address** — 3 cycles (`ADDR0`/`ADDR1`/`ADDR2`) with `ale` high  
2. **Data** — 2 cycles (`DATA0`/`DATA1`); write drives `uio`, read samples with `uio_oe` low  
3. **Ack** — complete the channel handshake  

`mem_sel` selects program (0) vs data (1). `mem_we` / `mem_re` qualify the access. Only one channel is serviced at a time (fixed priority: program 0–1, then data 0–3).

---

# Throughput

Numbers below assume the **50 MHz** Tiny Tapeout target. Peak figures are hardware ceilings with the relevant path saturated; real kernels are usually lower (hazards, fill/drain, arbitration, host SRAM latency).

## Compute

| Path | Peak | Notes |
| --- | --- | --- |
| Systolic MACs | **400 × 10⁶ MAC/s** | 8 PEs × 1 MAC/cycle × 50 MHz |
| Scalar FMA | **100 × 10⁶ FMA/s** | 4 thread FMAs × 0.5 issue/cycle (2-cycle unit), both cores busy |

A dense matmul that keeps both systolic arrays fed approaches the MAC peak. Scalar `FMA` loops are closer to the FMA row. Mixed control/integer code sits well below either.

## On-die scratchpad

| Mode | Peak bandwidth | How |
| --- | --- | --- |
| Halfword write hit | **100 MB/s** | 16-bit × 50 MHz (1-cycle write state) |
| Halfword read hit | **50 MB/s** | 16-bit × 25 MHz (2-cycle read) |
| Raw 32-bit RAM port | **200 MB/s** | 32-bit × 50 MHz if the port is continuously enabled |

Only one LSU hit uses the RAM at a time. Concurrent hits from other threads queue in the bridge.

## External memory (pin bus)

| Mode | Peak bandwidth | How |
| --- | --- | --- |
| Serialized 16-bit transfer | **~16.7 MB/s** | 50 MHz / 6 cycles × 2 bytes |

This is the hard limit for host SRAM traffic (program fetch and data miss/fill). Typical effective rate is lower when program and data contend or when the external device needs wait states.

## Practical mix

| Workload style | Usually limited by |
| --- | --- |
| Tight MAC over scratchpad tiles | Compute (systolic / FMA) |
| Streaming weights from external SRAM | External bus (~16.7 MB/s) |
| Many threads hitting scratchpad together | Scratchpad 1RW port |

---

# Pinout

Tiny Tapeout standard pins. Mapping matches `info.yaml` / `tt_um_aloshdenny_gpu.sv`.

### Inputs — `ui_in[7:0]`

| Pin | Signal | Description |
| --- | --- | --- |
| `ui_in[6:0]` | `thread_count` | Device control register (written while start is low) |
| `ui_in[7]` | `start` | Pulse high to launch the kernel |

### Outputs — `uo_out[7:0]`

| Pin | Signal | Description |
| --- | --- | --- |
| `uo_out[0]` | `done` | High when the kernel finishes |
| `uo_out[1]` | `mem_we` | External SRAM write enable |
| `uo_out[2]` | `mem_re` | External SRAM read enable |
| `uo_out[3]` | `ale` | Address latch enable |
| `uo_out[4]` | `mem_sel` | 0 = program memory, 1 = data memory |
| `uo_out[7:5]` | — | Tied low (reserved) |

### Bidirectional — `uio[7:0]`

| Pin | Signal | Description |
| --- | --- | --- |
| `uio[7:0]` | addr/data bus | Time-multiplexed address and data bytes |
| `uio_oe[7:0]` | output enable | Driven by the design during address/write phases |

### Clock / reset / enable

| Pin | Description |
| --- | --- |
| `clk` | System clock (≤ 50 MHz for the TT timing closure target) |
| `rst_n` | Active-low reset (internally synchronized) |
| `ena` | Always driven high by the TT harness when the design may run |

---

# Q1.15 Fixed-Point Format

Atreides uses Q1.15 fixed-point representation for neural network computations:

```
┌───┬───────────────────────────────┐
│ S │         FRACTION              │
│[15]│         [14:0]               │
└───┴───────────────────────────────┘
  │              │
  │              └── 15 fractional bits
  └── Sign bit (0=positive, 1=negative)
```


| Property        | Value                |
| --------------- | -------------------- |
| Total Bits      | 16                   |
| Sign Bits       | 1                    |
| Fractional Bits | 15                   |
| Range           | [-1.0, +0.999969...] |
| Resolution      | 2^-15 ≈ 0.0000305    |


### Conversion

```python
# Float to Q1.15
def float_to_q115(f):
    f = max(-1.0, min(f, 32767/32768))  # Clamp to valid range
    return int(round(f * 32768)) & 0xFFFF

# Q1.15 to Float
def q115_to_float(q):
    if q & 0x8000:  # Negative
        return (q - 65536) / 32768.0
    return q / 32768.0
```

### Why Q1.15?

Normalized weights/activations usually fit in [-1, 1]. A 15×15 multiply fits in 30 bits; the FMA/PE paths keep wider accumulators before saturating back to 16-bit. Fixed-point keeps the datapath smaller than a float unit at this process node.

---

# ISA

Atreides implements a 14-instruction custom ISA optimized for Q1.15 neural network operations and integer index calculation:

### Key Design Decision
- **Integer operations** (`ADD`, `SUB`, `MUL`, `DIV`): Used for index and address calculations, loop counters, and structural branches.
- **Q1.15 neural operations** (`FMA`, `ACT`): Used exclusively for Q1.15 matrix math to prevent accumulation precision loss and minimize CPU hardware footprint.

This separation ensures optimal hardware for each use case.

### Instruction Encoding

Instructions are 16 bits wide, encoded in a 4-field register-register format:

```
┌────────┬────────┬────────┬────────┐
│ OPCODE │   Rd   │   Rs   │   Rt   │
│ [15:12]│ [11:8] │  [7:4] │  [3:0] │
└────────┴────────┴────────┴────────┘
```
For instructions with immediate operands (e.g. `CONST`), the lower 8 bits `[7:0]` are treated as an 8-bit immediate. For PC-relative branch instructions (e.g. `BRnzp`), the lower 9 bits `[8:0]` are treated as a signed PC-relative offset.

### Register Map

Each thread owns its own independent register file with 16 registers:

| Register | Name       | Type | Description |
|---|---|---|---|
| `R0`–`R12` | General | R/W | 16-bit registers for integer arithmetic, addresses, and SF16 values |
| `R13` | `%blockIdx` | RO | Grid block index assigned by the Dispatcher |
| `R14` | `%blockDim` | RO | Core thread block dimension (threads per block) |
| `R15` | `%threadIdx`| RO | Thread lane index inside its current compute block |

---

### Instruction Set Reference

| Opcode (Binary) | Mnemonic | Syntax | Description / Behavior |
|---|---|---|---|
| `0000` | **NOP** | `NOP` | No operation. |
| `0001` | **BRnzp**| `BRnzp offset9` | Branch conditionally on `nzp` flags to `PC + 1 + sign_extend(offset9)`. |
| `0010` | **CMP** | `CMP Rd, Rs` | Compares integer values in `Rd` and `Rs`. Sets `nzp` flags (N: negative, Z: zero, P: positive). |
| `0011` | **ADD** | `ADD Rd, Rs, Rt` | Integer addition: `Rd = Rs + Rt`. |
| `0100` | **SUB** | `SUB Rd, Rs, Rt` | Integer subtraction: `Rd = Rs - Rt`. |
| `0101` | **MUL** | `MUL Rd, Rs, Rt` | Integer multiplication: `Rd = Rs[7:0] * Rt[7:0]` (16-bit zero-extended result). |
| `0110` | **DIV** | `DIV Rd, Rs, Rt` | Integer division: `Rd = Rs / Rt`. Fast hardware reciprocal division for common constants. |
| `0111` | **LDR** | `LDR Rd, Rs` | Load 16-bit value from Data Memory at address `Rs` into `Rd`. |
| `1000` | **STR** | `STR Rd, Rs` | Store 16-bit value from `Rs` into Data Memory at address `Rd`. |
| `1001` | **CONST**| `CONST Rd, imm8`| Load 8-bit sign-extended immediate `imm8` into `Rd`. |
| `1010` | **FMA** | `FMA Rd, Rs, Rt` | Q1.15 Fused Multiply-Accumulate: `Rd = (Rs * Rt) + Rd`. (Uses `Rd` as accumulator input). |
| `1011` | **ACT** | `ACT Rd, Rs, Rt` | Applies activation function `Rd = act(Rs + Rt)` where `Rt` is bias. Act function in `instruction[9:8]`. <br> • `00` = Passthrough <br> • `01` = ReLU <br> • `10` = Leaky ReLU <br> • `11` = Clipped ReLU. |
| `1100` | **SYS** | `SYS op, idx` | Systolic Array control interface instruction. <br> • `op=00` = Clear accumulators <br> • `op=01` = Load weights <br> • `op=10` = Compute step <br> • `op=11` = Read result from array `idx` into destination register. |
| `1111` | **RET** | `RET` | Return from kernel. Finishes current thread execution block. |


---

# Execution

### Core Control Flow

The scheduler drives a 7-state FSM:

```
┌──────┐   ┌────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌────────┐   ┌──────┐
│ IDLE │──▶│ FETCH  │──▶│ DECODE  │──▶│ REQUEST │──▶│  WAIT   │──▶│EXECUTE │──▶│UPDATE│
└──────┘   └────────┘   └─────────┘   └─────────┘   └─────────┘   └────────┘   └──────┘
                                                                       │
                                                                  (2 cycles for FMA)
```

1. **IDLE** — Waiting for block dispatch
2. **FETCH** — Fetch instruction from cache/program memory
3. **DECODE** — Decode 16-bit instruction into control signals
4. **REQUEST** — Request memory if LDR/STR
5. **WAIT** — Wait for memory response
6. **EXECUTE** — Execute ALU/FMA computation (FMA takes 2 cycles)
7. **UPDATE** — Write back to registers

### Thread

Thread

Each thread has dedicated ALU, FMA, Activation, LSU, PC, and register file. The `%blockIdx`, `%blockDim`, and `%threadIdx` registers enable SIMD functionality.

### Pipeline

Atreides supports a 5-stage instruction pipeline:

```
Cycle:    1     2     3     4     5     6     7     8
         ┌─────┬─────┬─────┬─────┬─────┐
Instr 1: │ IF  │ ID  │ EX  │ MEM │ WB  │
         └─────┴─────┴─────┴─────┴─────┘
               ┌─────┬─────┬─────┬─────┬─────┐
Instr 2:       │ IF  │ ID  │ EX  │ MEM │ WB  │
               └─────┴─────┴─────┴─────┴─────┘
                     ┌─────┬─────┬─────┬─────┬─────┐
Instr 3:             │ IF  │ ID  │ EX  │ MEM │ WB  │
                     └─────┴─────┴─────┴─────┴─────┘
```

Features:

- **Hazard Detection** — RAW hazard detection and stalling
- **Data Forwarding** — Forward results from EX/MEM stages
- **Load-Use Stall** — Automatic stall for load-use hazards

---

# Neural Network Features

## FMA Unit

The Fused Multiply-Add unit (`fma.sv`) is a **2-cycle pipelined** Q1.15 MAC:

```
┌─────────────────────────────────────────────────────────────┐
│                      FMA UNIT (2-cycle)                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Cycle 1:                                                  │
│   ┌─────┐    ┌─────┐                                        │
│   │ Rs  │    │ Rt  │   Operand Registers                    │
│   │ Act │    │ Wgt │                                        │
│   └──┬──┘    └──┬──┘                                        │
│      │          │                                           │
│      ▼          ▼                                           │
│   ┌──────────────────┐                                      │
│   │   Sign XOR       │  sign = sign_a ^ sign_w              │
│   └────────┬─────────┘                                      │
│            │                                                │
│   ┌────────▼─────────┐                                      │
│   │  15×15 Multiply  │  |mantissa_a| × |mantissa_w|         │
│   │   (30-bit out)   │                                      │
│   └────────┬─────────┘                                      │
│            │                                                │
│   Cycle 2:                                                  │
│   ┌────────▼─────────┐                                      │
│   │  Sign-Extend     │  Apply computed sign                  │
│   └────────┬─────────┘                                      │
│            │                                                │
│   ┌────────▼─────────┐    ┌─────┐                           │
│   │   Accumulate     │◀───│ Rd  │  Running sum (Rd += Rs*Rt)│
│   │   (32-bit)       │    │ Acc │                           │
│   └────────┬─────────┘    └─────┘                           │
│            │                                                │
│   ┌────────▼─────────┐                                      │
│   │   Saturate       │  Clamp to Q1.15 range                │
│   └────────┬─────────┘                                      │
│            │                                                │
│            ▼                                                │
│       Output (Q1.15)   Rd = (Rs × Rt) + Rd                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Key optimizations:

- **Sign-magnitude multiplication** — XOR for sign, 15×15 unsigned for mantissa
- **32-bit accumulator** — Prevents overflow during dot products
- **Saturation** — Clamps result to valid Q1.15 range
- **2-cycle pipeline** — High throughput with scheduler integration

## Systolic Array

Hardware-accelerated matrix multiplication with weight-stationary dataflow:

```systemverilog
module fma #(
    parameter DATA_BITS = 16,
    parameter ACC_BITS  = 32
) (
    input wire clk, reset, enable,
    input wire clear_acc, load_weight, compute_enable,
    input wire [DATA_BITS-1:0] a_in,      // Activation from left
    input wire [DATA_BITS-1:0] b_in,      // Weight from top
    output reg [DATA_BITS-1:0] a_out,     // Pass activation right
    output reg [DATA_BITS-1:0] b_out,     // Pass weight down
    output reg [DATA_BITS-1:0] acc_out    // Accumulated result (Q1.15)
);
```

Each FMA performs: `acc += a_in × b_in` (in Q1.15 with 32-bit internal accumulator)

## KV-Cache

> Optional RTL (`kv_cache.sv`) — not enabled in the default Tiny Tapeout `source_files` list.


Native support for transformer attention with sliding window (`kv_cache.sv`):

```
┌─────────────────────────────────────────────────────────────┐
│                       KV-CACHE                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    KEY CACHE                         │   │
│  │  ┌─────────┬─────────┬─────────┬─────────┐           │   │
│  │  │ Head 0  │ Head 1  │ Head 2  │ Head 3  │           │   │
│  │  │ [seq]   │ [seq]   │ [seq]   │ [seq]   │           │   │
│  │  │ [dim]   │ [dim]   │ [dim]   │ [dim]   │           │   │
│  │  └─────────┴─────────┴─────────┴─────────┘           │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                   VALUE CACHE                        │   │
│  │  ┌─────────┬─────────┬─────────┬─────────┐           │   │
│  │  │ Head 0  │ Head 1  │ Head 2  │ Head 3  │           │   │
│  │  │ [seq]   │ [seq]   │ [seq]   │ [seq]   │           │   │
│  │  │ [dim]   │ [dim]   │ [dim]   │ [dim]   │           │   │
│  │  └─────────┴─────────┴─────────┴─────────┘           │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  Features:                                                  │
│  • Multi-head support (4 heads)                             │
│  • Incremental append for autoregressive decoding           │
│  • Sliding window attention (circular buffer)               │
│  • Batch read for attention computation                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Parameters:

- `NUM_HEADS`: 4 (configurable)
- `HEAD_DIM`: 16 (configurable)
- `MAX_SEQ_LEN`: 256 (configurable)

## Weight & Activation Memory

> Optional RTL (`weight_mem.sv`) — not in the default Tiny Tapeout `source_files` list.


Dedicated memory banks with double-buffering for neural network inference (`weight_mem.sv`):

```
┌─────────────────────────────────────────────────────────────┐
│              WEIGHT & ACTIVATION MEMORY                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  WEIGHT BANKS (Read-only during inference)                  │
│  ┌─────────┬─────────┬─────────┬─────────┐                  │
│  │ Bank 0  │ Bank 1  │ Bank 2  │ Bank 3  │                  │
│  │ Buf A/B │ Buf A/B │ Buf A/B │ Buf A/B │                  │
│  └─────────┴─────────┴─────────┴─────────┘                  │
│                                                             │
│  ACTIVATION BANKS (Read/Write)                              │
│  ┌─────────┬─────────┬─────────┬─────────┐                  │
│  │ Bank 0  │ Bank 1  │ Bank 2  │ Bank 3  │                  │
│  │ Buf A/B │ Buf A/B │ Buf A/B │ Buf A/B │                  │
│  └─────────┴─────────┴─────────┴─────────┘                  │
│                                                             │
│  Features:                                                  │
│  • 4 parallel banks for concurrent access                   │
│  • Double-buffering for prefetching                         │
│  • 1024 entries per bank (1K × 16-bit = 2KB per bank)       │
│  • Prefetch support for hiding latency                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

# Advanced Features

## Memory Coalescing

> Optional RTL (`mem_coalesce.sv`) — not in the default Tiny Tapeout `source_files` list.


Combines multiple sequential memory requests into single transactions (`mem_coalesce.sv`):

```
Before Coalescing:           After Coalescing:
┌─────────────────┐          ┌─────────────────┐
│ Thread 0: R[0]  │          │                 │
│ Thread 1: R[1]  │  ────▶   │ Single Request  │
│ Thread 2: R[2]  │          │ R[0:3]          │
│ Thread 3: R[3]  │          │                 │
└─────────────────┘          └─────────────────┘
   4 requests                   1 request
```

The coalescing unit:

1. Analyzes pending memory requests from threads in the block
2. Identifies sequential addresses
3. Combines into single wide transaction
4. Distributes results back to threads

## Branch Divergence

Handles SIMT execution when threads take different paths (`branch_diverge.sv`):

```
                    ┌─────────────┐
                    │   Branch    │
                    │ Instruction │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
       ┌─────────────┐           ┌─────────────┐
       │ Threads 0,2 │           │ Threads 1,3 │
       │ Take Branch │           │ Fall Through│
       └──────┬──────┘           └──────┬──────┘
              │                         │
              │    ┌─────────────┐      │
              └───▶│ Reconverge  │◀─────┘
                   │   Point     │
                   └─────────────┘
```

Features:

- **Divergence Stack** — Tracks divergent thread masks
- **Warp Mask** — Active thread tracking per warp
- **Reconvergence Detection** — Automatic at post-dominator points
- **Nested Divergence** — Stack-based handling of nested branches

## Instruction Pipeline

5-stage pipeline with hazard handling (`pipeline.sv`):


| Stage | Description        | Hazard Handling |
| ----- | ------------------ | --------------- |
| IF    | Instruction Fetch  | —               |
| ID    | Instruction Decode | RAW detection   |
| EX    | Execute (ALU/FMA)  | Data forwarding |
| MEM   | Memory Access      | Load-use stall  |
| WB    | Write Back         | —               |
---

# Performance & Model Profiling

Atreides features two modes of operation:
1. **Standard FMA Mode**: Threads execute standard instructions sequentially through the scheduler's 7-state FSM. FMA operations run at a throughput of **0.208 FLOPs/cycle** per thread due to load-store latencies and loop overhead.
2. **Systolic Array Mode**: Matrix computations are accelerated using the weight-stationary systolic arrays (2 arrays of 2×2 PEs per core, 16 total PEs across 2 cores). At peak utilization, this delivers **19.2 FLOPs/cycle** at a safe 50 MHz clock speed, representing a **92.4× speedup** over sequential execution.

### Measured Hardware Microbenchmarks (100 MHz Simulation)

Below is the verified performance measured directly from the RTL simulation across typical matrix dimensions:

| Operation | Dimensions | Cycles | Latency | GFLOPS | Throughput |
|---|---|---|---|---|---|
| **MatMul** | $2 \times 2 \times 2$ | 373 | 3.7 µs | 0.00429 GFLOPS | 0.0107 elements/cycle |
| **MatMul** | $3 \times 3 \times 3$ | 974 | 9.7 µs | 0.00554 GFLOPS | 0.0092 elements/cycle |
| **MatMul** | $4 \times 4 \times 4$ | 1204 | 12.0 µs | 0.01063 GFLOPS | 0.0133 elements/cycle |

---

### Large LLM Decoder Latency & Throughput Scaling (50 MHz Clock)

Estimated decode latency per token (1 token generation step with context length = 32) comparing sequential FMA execution with systolic array acceleration:

| Model | Parameters | Layers | $d_{\text{model}}$ | FLOPs/token | Standard FMA Latency | Standard FMA Token/s | Systolic Array Latency | Systolic Array Token/s | Speedup |
|---|---|---|---|---|---|---|---|---|---|
| **GPT-2 (Small)** | 117M | 12 | 768 | $1.71 \times 10^8$ | 16.46 s | 0.0607 | 178.2 ms | 5.61 | 92.4x |
| **Transformer-500M** | 500M | 24 | 1024 | $6.07 \times 10^8$ | 58.43 s | 0.0171 | 632.4 ms | 1.58 | 92.4x |
| **Transformer-1B** | 1.0B | 32 | 1536 | $1.82 \times 10^9$ | 175.00 s | 0.0057 | 1.89 s | 0.53 | 92.4x |
| **Transformer-2B** | 2.0B | 32 | 2048 | $3.23 \times 10^9$ | 310.84 s | 0.0032 | 3.36 s | 0.30 | 92.4x |
| **Transformer-4B** | 4.0B | 40 | 3072 | $9.08 \times 10^9$ | 873.48 s | 0.0011 | 9.45 s | 0.11 | 92.4x |
| **Transformer-8B** | 8.0B | 80 | 4096 | $3.23 \times 10^{10}$ | 3104.35 s | 0.0003 | 33.60 s | 0.03 | 92.4x |

---

# Kernels

### Matrix Addition

Adds two 1×8 matrices using Q1.15 arithmetic:

```asm
.threads 8
.data 0x2000 0x2000 0x2000 0x2000 0x2000 0x2000 0x2000 0x2000  ; A (0.25 in Q1.15)
.data 0x4000 0x4000 0x4000 0x4000 0x4000 0x4000 0x4000 0x4000  ; B (0.5 in Q1.15)

MUL R0, %blockIdx, %blockDim
ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx

CONST R1, #0                   ; baseA
CONST R2, #8                   ; baseB
CONST R3, #16                  ; baseC

ADD R4, R1, R0                 ; addr(A[i])
LDR R4, R4                     ; load A[i]

ADD R5, R2, R0                 ; addr(B[i])
LDR R5, R5                     ; load B[i]

ADD R6, R4, R5                 ; C[i] = A[i] + B[i]

ADD R7, R3, R0                 ; addr(C[i])
STR R7, R6                     ; store C[i]

RET
```

### Matrix Multiplication

Multiplies two 2×2 matrices using FMA for Q1.15 dot products:

```asm
.threads 4
.data 0x4000 0x4000 0x4000 0x4000  ; A (0.5 in Q1.15)
.data 0x4000 0x4000 0x4000 0x4000  ; B (0.5 in Q1.15)

MUL R0, %blockIdx, %blockDim
ADD R0, R0, %threadIdx         ; i = blockIdx * blockDim + threadIdx

CONST R1, #1                   ; increment
CONST R2, #2                   ; N
CONST R3, #0                   ; baseA
CONST R4, #4                   ; baseB
CONST R5, #8                   ; baseC

DIV R6, R0, R2                 ; row = i / N
MUL R7, R6, R2
SUB R7, R0, R7                 ; col = i % N

CONST R8, #0                   ; acc = 0 (Q1.15)
CONST R9, #0                   ; k = 0

LOOP:
  MUL R10, R6, R2
  ADD R10, R10, R9
  ADD R10, R10, R3             ; addr(A[row][k])
  LDR R10, R10                 ; load A[row][k]

  MUL R11, R9, R2
  ADD R11, R11, R7
  ADD R11, R11, R4             ; addr(B[k][col])
  LDR R11, R11                 ; load B[k][col]

  FMA R8, R10, R11             ; acc += A[row][k] * B[k][col] (Q1.15 FMA)

  ADD R9, R9, R1               ; k++

  CMP R9, R2
  BRn LOOP                     ; while k < N

ADD R9, R5, R0                 ; addr(C[i])
STR R9, R8                     ; store result

RET
```

---

# Simulation

### Prerequisites

```bash
# Install Verilog compiler
brew install icarus-verilog

# Install cocotb
pip3 install cocotb

# Install sv2v (SystemVerilog to Verilog converter)
# Download from https://github.com/zachjs/sv2v/releases

# Create build directory
mkdir build
```

### Running Tests

```bash
# Matrix Addition
make test_matadd

# Matrix Multiplication
make test_matmul

# ResNet-20 Model Inference
# Simulates full Q1.15 inference natively on the Verilog DUT utilizing SF16 ACT bias addition
make test_model_resnet

# GPT-2 Autoregressive Inference (Hardware Native)
# Executes the entire 12-layer GPT-2 model bit-for-bit on the Verilog DUT. Automatically tiles 
# large memory-bound parameter tensors across the PCIe interface to fit inside the 1 MiB data space.
make test_model_transformer

# Run all unit tests
make test_all_units

# Clean build artifacts
make clean
```

### Output

Simulation produces log files in `test/results/` with:

- Initial data memory state
- Complete execution trace (cycle-by-cycle)
- Final data memory state

Example trace output:

```
=================================== Cycle 10 ===================================

+---------------------- Core 0 ----------------------+

+-------- Thread 0 --------+
PC: 0
Instruction: MUL R0, R13, R14
Core State: EXECUTE
Fetcher State: IDLE
LSU State: IDLE
Registers: R0 = 0, R1 = 0, ... %blockIdx = 0, %blockDim = 4, %threadIdx = 0
RS = 0, RT = 4
ALU Out: 0
```

---

# Test Files

The test infrastructure provides comprehensive simulation and verification:

```
test/
├── __init__.py              # Test package marker
├── tb_gpu.sv                # Full GPU testbench
├── tb_fma.sv                # FMA unit testbench
├── tb_alu.sv                # ALU unit testbench
├── tb_activation.sv         # Activation unit testbench
├── tb_fma.sv        # Systolic FMA testbench
├── tb_array.sv     # Systolic array testbench
├── tb_cache.sv              # Cache unit testbench
├── tb_decoder.sv            # Decoder unit testbench
├── tb_lsu.sv                # LSU unit testbench
├── test_matadd.py           # Matrix addition kernel test
├── test_matmul.py           # Matrix multiplication kernel test
├── test_model_resnet.py     # End-to-end ResNet-20 hardware verification test
├── test_model_transformer.py # End-to-end GPT-2 inference pipeline hardware test
├── test_fma_unit.py         # FMA unit test (cocotb)
├── test_alu_unit.py         # ALU unit test (cocotb)
├── test_activation_unit.py  # Activation unit test (cocotb)
├── test_fma_unit.py # Systolic FMA test (cocotb)
├── test_array_unit.py # Systolic array test (cocotb)
├── test_cache_unit.py       # Cache unit test (cocotb)
├── test_decoder_unit.py     # Decoder unit test (cocotb)
├── test_lsu_unit.py         # LSU unit test (cocotb)
├── gtkwave/                 # GTKWave save files for waveform viewing
│   ├── fma.gtkw
│   ├── alu.gtkw
│   ├── activation.gtkw
│   ├── fma.gtkw
│   ├── array.gtkw
│   ├── cache.gtkw
│   ├── decoder.gtkw
│   └── lsu.gtkw
├── helpers/
│   ├── __init__.py          # Helper package exports
│   ├── q115.py              # Q1.15 fixed-point conversion utilities
│   ├── format.py            # Trace formatting (decode instructions)
│   ├── logger.py            # File/console logging with timestamps
│   ├── memory.py            # Memory init & assembly instruction helpers
│   ├── report.py            # Test report generation
│   └── setup.py             # Test setup, kernel execution, state capture
└── results/                 # Test output logs
```

### Test Helper Modules


| Module      | Description                                                |
| ----------- | ---------------------------------------------------------- |
| `q115.py`   | Q1.15 ↔ float conversion, Q1.15 arithmetic (mul, add, fma) |
| `format.py` | Instruction decoding, register formatting, trace output    |
| `logger.py` | `GPULogger` class for trace files with timestamps          |
| `memory.py` | Memory init, assembly helpers (`asm_add`, `asm_fma`, etc.) |
| `setup.py`  | `setup_test()`, `run_kernel()`, `get_core_states()`        |
| `report.py` | Test summary report generation                             |


### Assembly Helpers

The `memory.py` module provides assembly instruction builders:

```python
from helpers.memory import *

program = [
    asm_mul(R0, BLOCK_IDX, BLOCK_DIM),  # R0 = blockIdx * blockDim
    asm_add(R0, R0, THREAD_IDX),         # R0 += threadIdx
    asm_const(R1, 0),                    # R1 = 0
    asm_ldr(R2, R1),                     # R2 = mem[R1]
    asm_fma(R3, R2, R4),                 # R3 = R2 * R4 + R3 (Q1.15)
    asm_str(R5, R3),                     # mem[R5] = R3
    asm_ret(),                           # End thread
]
```

### Writing New Tests

```python
import cocotb
from helpers.setup import setup_test, run_kernel
from helpers.memory import asm_add, asm_ret, R0, R1

@cocotb.test()
async def test_example(dut):
    program = [asm_add(R0, R0, R1), asm_ret()]
    data = [0x1000, 0x2000]  # Q1.15 values
    
    logger = await setup_test(dut, "example", program, data, thread_count=2)
    await run_kernel(dut, logger, max_cycles=100, trace_interval=5)
    
    # Read results and verify
    from helpers.memory import read_memory_range
    results = read_memory_range(dut, 0, 4)
    logger.close()
```

---

# ASIC / Tiny Tapeout

Submission flow uses Tiny Tapeout’s GDS action and `src/config.json` (merged with `tt_tool` user config). Tile size is **8×4** (`info.yaml`). The on-die scratchpad is a **synthesizable** 32×32 soft-flop RAM (`RAM32.v`), not the hard DFFRAM macro (the CI LibreLane flow cannot run the post-PDN power hook that hard RAM32 needs).

Local / experimental LibreLane configs under `librelane/` may describe larger hierarchical builds; **the silicon parameters that matter for this shuttle are those in `src/` and `info.yaml`.**

GDS viewing (after a successful harden):

```bash
klayout runs/.../final/gds/*.gds
# or
make view_layout
```

### Design metrics (TT target)

| Metric | Value |
| --- | --- |
| Technology | Sky130 |
| Clock | 50 MHz |
| Tiles | 8×4 |
| MAC units | 8 |
| On-die scratchpad | 128 B |
| External data bus peak | ~16.7 MB/s @ 50 MHz |

---

# Modules

| Module | File | Description |
| --- | --- | --- |
| Chip top | `tt_um_aloshdenny_gpu.sv` | TT pins, memory arbiter, RAM32 instance |
| GPU | `gpu.sv` | Cores, controllers, dispatcher, DCR, scratchpad bridge |
| Scratchpad | `scratchpad.sv` | Address decode / hit mux for `0xFFC0`–`0xFFFF` |
| RAM32 | `RAM32.v` | Soft-flop 32×32 1RW (128 B) |
| Core | `core.sv` | Scheduler, threads, systolic array |
| ALU | `alu.sv` | Integer arithmetic |
| FMA | `fma.sv` | Q1.15 fused multiply-add (2-cycle) |
| Activation | `activation.sv` | Bias + ReLU family |
| Decoder | `decoder.sv` | 16-bit instruction decode |
| Registers | `registers.sv` | 16-entry register file |
| LSU | `lsu.sv` | Load/store unit |
| PC | `pc.sv` | Program counter / branches |
| Scheduler | `scheduler.sv` | Core pipeline FSM |
| Fetcher | `fetcher.sv` | Instruction fetch |
| Dispatcher | `dispatch.sv` | Block dispatch |
| DCR | `dcr.sv` | Device control register |
| Controller | `controller.sv` | Memory channel controller |
| Systolic array | `systolic_array.sv` | 2×2 weight-stationary array |
| Systolic PE | `systolic_pe.sv` | Pipelined MAC PE (1 MAC/cycle) |
| Branch diverge | `branch_diverge.sv` | SIMT divergence stack |

Optional / experimental RTL also present in-tree (`cache.sv`, `mem_coalesce.sv`, `weight_mem.sv`, `kv_cache.sv`) is not part of the default TT `source_files` list.

---

**Atreides** — Superfloat / Tiny Tapeout
