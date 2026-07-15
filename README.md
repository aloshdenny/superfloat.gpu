# Atreides



**Superfloat's Atreides: A Q1.15 Fixed-Point Neural Network Accelerator**

*Version 3.0 — Artix-7 FPGA-Sized Architecture with Librelane 2*



---

A minimal GPU implementation in SystemVerilog optimized for neural network inference with Q1.15 fixed-point arithmetic, systolic arrays, and LLM-specific optimizations.

Built with fully documented SystemVerilog, complete documentation on architecture & ISA, working matrix addition/multiplication kernels with FMA support, and full support for kernel simulation & execution traces.

## Key Features (v3.0)


| Feature               | Specification                                                            |
| --------------------- | ------------------------------------------------------------------------ |
| **Compute Cores**     | 1 core                                                                   |
| **Threads/Block**     | 4 threads per block                                                      |
| **Systolic Arrays**   | 2 arrays per core, 2×2 FMAs each                                         |
| **Total FMAs**         | 8 processing elements (1 core × 2 arrays × 4)                            |
| **Data Memory**       | 2^19 rows × 16-bit (1 MiB total data space)                              |
| **Program Memory**    | 512 instructions                                                         |
| **Memory Channels**   | 4 data + 1 program channels                                              |
| **Instruction Cache** | 2 entries per core                                                       |
| **Arithmetic**        | Q1.15 fixed-point                                                        |
| **Clock (GPU top)**   | 50 MHz (20 ns period)                                                    |
| **Technology**        | SkyWater 130nm (sky130A)                                                 |
| **Target FPGA**       | Xilinx Artix-7 (XC7A100T)                                                |
| **Physical Design**   | Hierarchical Librelane 2 (nix-based)                                     |


### Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [GPU](#gpu)
  - [Memory](#memory)
  - [Core](#core)
  - [Systolic Arrays](#systolic-arrays)
- [Q1.15 Fixed-Point Format](#q115-fixed-point-format)
- [ISA](#isa)
- [Execution](#execution)
  - [Core](#core-1)
  - [Thread](#thread)
  - [Pipeline](#pipeline)
- [Neural Network Features](#neural-network-features)
  - [FMA Unit](#fma-unit)
  - [Systolic Array](#systolic-array-1)
  - [KV-Cache](#kv-cache)
  - [Weight & Activation Memory](#weight--activation-memory)
- [Advanced Features](#advanced-features)
  - [Memory Coalescing](#memory-coalescing)
  - [Branch Divergence](#branch-divergence)
  - [Instruction Pipeline](#instruction-pipeline)
- [Kernels](#kernels)
  - [Matrix Addition](#matrix-addition)
  - [Matrix Multiplication](#matrix-multiplication)
- [Simulation](#simulation)
- [Test Files](#test-files)
- [ASIC Generation (Librelane 2)](#asic-generation-librelane)
  - [Macro: fma](#macro-fma)
  - [Macro: array](#macro-array)
  - [Macro: core](#macro-core)
  - [Macro: gpu](#macro-gpu)
- [Modules](#modules)

---

# Overview

**Atreides** is a neural network accelerator designed from the ground up for efficient fixed-point inference. Unlike traditional GPUs that focus on floating-point graphics, Atreides is optimized for the specific computational patterns found in modern deep learning:

- **Q1.15 Fixed-Point Arithmetic** — Bounded [-1, 1] range perfect for normalized weights and activations
- **Fused Multiply-Add (FMA)** — 2-cycle pipelined MAC operations with 32-bit internal accumulation
- **Systolic Arrays** — 2 arrays of 2×2 FMAs per core for efficient parallelism (8 FMAs total)
- **KV-Cache** — Native support for transformer attention mechanisms
- **Memory Coalescing** — Efficient memory access patterns for tensor operations

## Design Philosophy

Atreides follows the principle of **separation of concerns**:

- **Integer arithmetic** (ADD, SUB, MUL, DIV) for indexing, addressing, and control flow
- **Q1.15 fixed-point** (FMA) exclusively for neural network computations

This separation allows optimal hardware for each use case while maintaining a simple, understandable architecture.

## Architecture Summary (v3.0)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            ATREIDES GPU v3.0                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────────┐  ┌──────────────────────────┐             │
│  │         Core 0           │  │         Core 1           │             │
│  │  ┌────────────────────┐  │  │  ┌────────────────────┐  │             │
│  │  │  32× SA 4x4 FMAs   │  │  │  │  32× SA 4x4 FMAs   │  │             │
│  │  └────────────────────┘  │  │  └────────────────────┘  │             │
│  │     4 Threads/Block      │  │     4 Threads/Block      │             │
│  └──────────────────────────┘  └──────────────────────────┘             │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │              Memory Controllers (8 Data + 2 Program)            │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │           Data Memory (2^19 × 16-bit) + Program Memory          │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

# Architecture



## GPU

Atreides executes a single kernel at a time with the following launch sequence:

1. Load global program memory with the kernel code
2. Load data memory with the necessary data (weights, activations in Q1.15)
3. Specify the number of threads to launch in the device control register
4. Launch the kernel by setting the start signal to high

The GPU top-level (`gpu.sv`) consists of:


| Unit                      | Description                                       |
| ------------------------- | ------------------------------------------------- |
| Device Control Register   | Stores kernel execution metadata (`thread_count`) |
| Dispatcher                | Distributes thread blocks to 1 compute core       |
| Compute Cores             | 1 processing unit with systolic arrays            |
| Data Memory Controller    | 4-channel controller (1 core × 4 threads)         |
| Program Memory Controller | 1-channel read-only controller                    |


### Top-Level Parameters (`gpu.sv`)


| Parameter                  | Default | Description              |
| -------------------------- | ------- | ------------------------ |
| `DATA_MEM_ADDR_BITS`       | 19      | 1 MiB data memory space  |
| `DATA_MEM_DATA_BITS`       | 16      | Q1.15 word width         |
| `DATA_MEM_NUM_CHANNELS`    | 4       | 1 core × 4 threads       |
| `PROGRAM_MEM_ADDR_BITS`    | 12      | 4096 instructions        |
| `PROGRAM_MEM_DATA_BITS`    | 16      | 16-bit instruction width |
| `PROGRAM_MEM_NUM_CHANNELS` | 1       | 1 per core               |
| `NUM_CORES`                | 1       | Compute cores            |
| `THREADS_FMAR_BLOCK`        | 4       | Threads per block        |
| `SYSTOLIC_SIZE`            | 2       | 2×2 FMA grid             |
| `NUM_ARRAYS`      | 2       | Arrays per core          |


### Device Control Register

Stores the `thread_count` — the total number of threads to launch for the active kernel.

### Dispatcher

Manages distribution of threads to compute cores, organizing threads into **blocks** that execute in parallel on a single core.

## Memory

### Global Memory Specifications (v3.0)


| Memory Type    | Address Bits | Data Bits | Size      | Description                          |
| -------------- | ------------ | --------- | --------- | ------------------------------------ |
| Data Memory    | 19 bits      | 16 bits   | 1 MiB     | Stores weights, activations, results |
| Program Memory | 12 bits      | 16 bits   | 4096 rows | Kernel instructions                  |


### Memory Controllers

Handle throttling of memory requests based on external bandwidth and relay responses back to compute cores.


| Controller     | Channels | Purpose                |
| -------------- | -------- | ---------------------- |
| Data Memory    | 4        | 1 core × 4 threads     |
| Program Memory | 1        | 1 per core (read-only) |


### Instruction Cache

```
┌─────────────────────────────────────────┐
│           INSTRUCTION CACHE (64)        │
├─────────────────────────────────────────┤
│  TAG  │  VALID  │  INSTRUCTION DATA     │
├───────┼─────────┼───────────────────────┤
│ 6-bit │  1-bit  │      16-bit           │
└───────┴─────────┴───────────────────────┘
```

64-entry direct-mapped cache that stores recently fetched instructions, reducing program memory access latency.

## Core

Each core (`core.sv`) processes one **block** at a time with dedicated resources per thread:


| Resource      | Per Thread | Description                                      |
| ------------- | ---------- | ------------------------------------------------ |
| ALU           | Yes        | Integer arithmetic (ADD, SUB, MUL, DIV, CMP)     |
| FMA           | Yes        | Q1.15 fused multiply-add (2-cycle pipelined)     |
| Activation    | Yes        | Bias addition + ReLU/LeakyReLU/ClippedReLU       |
| LSU           | Yes        | Load-store unit for memory access                |
| PC            | Yes        | Program counter (12-bit, NZP-conditioned branch) |
| Register File | Yes        | 16 registers (13 R/W + 3 read-only)              |


### Core Parameters


| Parameter             | Default | Description               |
| --------------------- | ------- | ------------------------- |
| `THREADS_FMAR_BLOCK`   | 4       | Threads per block         |
| `SYSTOLIC_SIZE`       | 4       | 4×4 FMA grid               |
| `NUM_ARRAYS` | 32      | Arrays per core           |
| `CACHE_SIZE`          | 64      | Instruction cache entries |


### Core Submodules

Each core instantiates:


| Submodule        | Count          | Description                                                    |
| ---------------- | -------------- | -------------------------------------------------------------- |
| `cache`          | 1              | 64-entry instruction cache                                     |
| `fetcher`        | 1              | Async instruction fetch from cache/memory                      |
| `decoder`        | 1              | 16-bit instruction decoder                                     |
| `scheduler`      | 1              | 7-state pipeline FSM (instantiates `branch_diverge`)           |
| `alu`            | 4 (per thread) | Integer ALU                                                    |
| `fma`            | 4 (per thread) | Q1.15 FMA unit                                                 |
| `activation`     | 4 (per thread) | Bias & activation function                                     |
| `lsu`            | 4 (per thread) | Load-store unit                                                |
| `registers`      | 4 (per thread) | 16-register file                                               |
| `pc`             | 4 (per thread) | Program counter                                                |
| `array` | 2              | 4×4 weight-stationary systolic arrays                          |
| `mem_coalesce`   | 1              | Memory coalescing unit                                         |
| `weight_mem`     | 1              | Weight/activation banks (4 banks, 1024 depth, double-buffered) |
| `kv_cache`       | 1              | KV-cache (4 heads, 16 dim, 256 seq len)                        |


## Systolic Arrays

Atreides v3.0 features 2 systolic arrays per core (2 total), each a 2×2 grid of processing elements:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        SYSTOLIC ARRAYS (per core)                       │
│                         (2 Arrays × 2×2 FMAs)                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐                     │
│  │      Array 0         │  │      Array 1         │                     │
│  │      2×2 FMAs         │  │      2×2 FMAs         │                     │
│  │     (4 FMAs)          │  │     (4 FMAs)          │                     │
│  └──────────────────────┘  └──────────────────────┘                     │
│                                                                         │
│  8 FMAs total                                                           │
│                                                                         │
│  Control:                                                               │
│  • array_select[0]    - Select individual array (0–1)                   │
│  • clear_acc          - Clear accumulators                              │
│  • load_weights       - Load weight matrix (weight-stationary)          │
│  • compute_enable     - Enable MAC operations                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

Each 4×4 systolic array (`array.sv`, parameterized `ARRAY_SIZE=4`, `PIFMA_INTERVAL=2`):

```
        ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐
  a[0]──│ FMA  │───│ FMA  │───│ FMA  │───│ FMA  │──▶
        │ 0,0 │   │ 0,1 │   │ 0,2 │   │ 0,3 │
        └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
           │         │         │         │
        ┌──▼──┐   ┌──▼──┐   ┌──▼──┐   ┌──▼──┐
  a[1]──│ FMA  │───│ FMA  │───│ FMA  │───│ FMA  │──▶
        │ 1,0 │   │ 1,1 │   │ 1,2 │   │ 1,3 │
        └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
           │         │         │         │
        ┌──▼──┐   ┌──▼──┐   ┌──▼──┐   ┌──▼──┐
  a[2]──│ FMA  │───│ FMA  │───│ FMA  │───│ FMA  │──▶
        │ 2,0 │   │ 2,1 │   │ 2,2 │   │ 2,3 │
        └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
           │         │         │         │
        ┌──▼──┐   ┌──▼──┐   ┌──▼──┐   ┌──▼──┐
  a[3]──│ FMA  │───│ FMA  │───│ FMA  │───│ FMA  │──▶
        │ 3,0 │   │ 3,1 │   │ 3,2 │   │ 3,3 │
        └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
           ▼         ▼         ▼         ▼
         b[0]      b[1]      b[2]      b[3]
```

### Systolic Array Parameters


| Parameter       | Default | Description                                      |
| --------------- | ------- | ------------------------------------------------ |
| `DATA_BITS`     | 16      | Q1.15 word width                                 |
| `ARRAY_SIZE`    | 4       | NxN FMA grid dimension                            |
| `PIFMA_INTERVAL` | 2       | Pipeline registers every N FMAs (for routability) |


### Systolic FMA Parameters


| Parameter   | Default | Description                |
| ----------- | ------- | -------------------------- |
| `DATA_BITS` | 16      | Q1.15 I/O width            |
| `ACC_BITS`  | 32      | Internal accumulator width |


Each FMA (`fma.sv`) uses a **3-stage pipelined sign-magnitude MAC**:

- **Stage 0** — Latch inputs, compute sign (XOR), extract absolute values
- **Stage 1** — 15×15 unsigned multiply (30-bit product)
- **Stage 2** — Sign-extend product, accumulate into 32-bit register, saturate to Q1.15 output

### Module Hierarchy

```
└── GPU (gpu.sv)
    ├── DCR (dcr.sv)
    ├── Data Memory Controller (controller.sv, 8 channels)
    ├── Program Memory Controller (controller.sv, 2 channels, read-only)
    ├── Dispatcher (dispatch.sv)
    └── Core ×2 (core.sv)
        ├── Instruction Cache (cache.sv, 64 entries)
        ├── Fetcher (fetcher.sv)
        ├── Decoder (decoder.sv)
        ├── Scheduler (scheduler.sv)
        │   └── Branch Divergence (branch_diverge.sv)
        ├── Per-Thread ×4:
        │   ├── ALU (alu.sv)
        │   ├── FMA (fma.sv)
        │   ├── Activation (activation.sv)
        │   ├── LSU (lsu.sv)
        │   ├── Registers (registers.sv)
        │   └── PC (pc.sv)
        ├── Systolic Array ×2 (array.sv, 4×4)
        │   └── Systolic FMA ×16 (fma.sv)
        ├── Memory Coalescing (mem_coalesce.sv)
        ├── Weight Memory (weight_mem.sv)
        └── KV-Cache (kv_cache.sv)
```

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

1. **Normalized Range** — Neural network weights and activations are typically normalized to [-1, 1]
2. **Efficient Multiplication** — 15×15 bit multiplication fits in 30 bits
3. **No Overflow in Accumulation** — Using 32-bit accumulators prevents overflow
4. **Hardware Efficient** — Simpler than floating-point, lower power consumption

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

1. Analyzes pending memory requests from all 4 threads
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
2. **Systolic Array Mode**: Matrix computations are accelerated using the weight-stationary systolic arrays (2 arrays of 2×2 PEs per core, 8 total PEs). At peak utilization, this delivers **9.6 FLOPs/cycle** at a safe 50 MHz clock speed, representing a **46.2× speedup** over sequential execution.

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
| **GPT-2 (Small)** | 117M | 12 | 768 | $1.71 \times 10^8$ | 16.46 s | 0.0607 | 356.4 ms | 2.81 | 46.2x |
| **Transformer-500M** | 500M | 24 | 1024 | $6.07 \times 10^8$ | 58.43 s | 0.0171 | 1.26 s | 0.79 | 46.2x |
| **Transformer-1B** | 1.0B | 32 | 1536 | $1.82 \times 10^9$ | 175.00 s | 0.0057 | 3.79 s | 0.26 | 46.2x |
| **Transformer-2B** | 2.0B | 32 | 2048 | $3.23 \times 10^9$ | 310.84 s | 0.0032 | 6.73 s | 0.15 | 46.2x |
| **Transformer-4B** | 4.0B | 40 | 3072 | $9.08 \times 10^9$ | 873.48 s | 0.0011 | 18.91 s | 0.05 | 46.2x |
| **Transformer-8B** | 8.0B | 80 | 4096 | $3.23 \times 10^{10}$ | 3104.35 s | 0.0003 | 67.20 s | 0.01 | 46.2x |

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
    
    logger = await setup_test(dut, "example", program, data, thread_count=4)
    await run_kernel(dut, logger, max_cycles=100, trace_interval=5)
    
    # Read results and verify
    from helpers.memory import read_memory_range
    results = read_memory_range(dut, 0, 4)
    logger.close()
```

---

# ASIC Generation (Librelane 2)

Atreides v3.0 uses a **hierarchical physical design** approach with **Librelane 2** for the RTL-to-GDSII flow. Each level of the module hierarchy is synthesized, placed, and routed independently, then integrated as a hardened macro in the level above.

Librelane 2 is **nix-based**, reproducible, and runs **directly inside the project repository** — no Docker, no `flow.tcl`, no design copying.

---

## Prerequisites

```bash
# Install Nix
curl -L https://nixos.org/nix/install | sh

# Clone Librelane 2
git clone https://github.com/librelane ~/librelane
cd ~/librelane

# Enter Librelane 2 environment
nix-shell
```

Librelane 2 tools (OpenROAD, Yosys, Magic, KLayout, etc.) are made available **only inside the nix shell**.

---

## Directory Layout

Each physical block has its own directory with a `config.json`:

```
librelane/
├── fma/
│   └── config.json
├── array/
│   └── config.json
├── core/
│   └── config.json
└── gpu/
    └── config.json
```

Each directory is executed independently using `librelane config.json`.

---

## Hierarchical Build

The hierarchy matches the RTL module composition. Each level is built bottom-up:

```
└── GPU (1 core)                           ← librelane/gpu/
    └── Core (4 threads + 2 SA + subsystems)   ← librelane/core/
        └── Systolic Array (2×2 FMAs)           ← librelane/array/
            └── Systolic FMA (3-stage MAC)      ← librelane/fma/
```

### Build Order

```bash
# 1. Build the FMA macro
cd librelane/fma
librelane config.json

# 2. Build the 2×2 systolic array
cd ../array
librelane config.json

# 3. Build the compute core (4 threads + 2 arrays + subsystems)
cd ../core
librelane config.json

# 4. Build the full GPU (1 core + controllers + dispatcher)
cd ../gpu
librelane config.json
```

---

## Macro Specifications

### Per-Level Summary


| Macro            | Clock Period | Frequency | Core Util | Key Settings                              |
| ---------------- | ------------ | --------- | --------- | ----------------------------------------- |
| `fma`    | 5 ns         | 200 MHz   | Auto      | Antenna repair                            |
| `array` | 6 ns         | 166 MHz   | Auto      | Antenna repair, 4×4 FMA grid               |
| `core`           | 8 ns         | 125 MHz   | Auto      | 17 source files, antenna repair           |
| `gpu`            | 8 ns         | 125 MHz   | 40%       | Antenna repair, timing/routability driven |


---

### Macro: `fma`

The smallest physical unit — a single Q1.15 processing element with 3-stage pipelined sign-magnitude MAC and 32-bit accumulator.

**Config** (`librelane/fma/config.json`):

```json
{
  "DESIGN_NAME": "fma",
  "VERILOG_FILES": ["dir::../../src/fma.sv"],
  "CLOCK_PORT": "clk",
  "CLOCK_FMARIOD": 15,
  "RUN_ANTENNA_REPAIR": true
}
```

**RTL Parameters:**


| Parameter   | Value | Description          |
| ----------- | ----- | -------------------- |
| `DATA_BITS` | 16    | Q1.15 I/O width      |
| `ACC_BITS`  | 32    | Internal accumulator |


**Ports:** `clk`, `reset`, `enable`, `clear_acc`, `load_weight`, `compute_enable`, `a_in[15:0]`, `b_in[15:0]`, `a_out[15:0]`, `b_out[15:0]`, `acc_out[15:0]`

**Architecture:** 3-stage pipeline — sign XOR + abs → 15×15 unsigned multiply → sign-extend + accumulate + saturate.

---

### Macro: `array`

A 4×4 weight-stationary systolic array composed of 16 FMAs with pipeline registers every 2 FMAs for improved routability.

**Config** (`librelane/array/config.json`):

```json
{
  "DESIGN_NAME": "array",
  "VERILOG_FILES": [
    "dir::../../src/array.sv",
    "dir::../../src/fma.sv"
  ],
  "CLOCK_PORT": "clk",
  "CLOCK_FMARIOD": 30,
  "RUN_ANTENNA_REPAIR": true
}
```

**RTL Parameters:**


| Parameter       | Value | Description                    |
| --------------- | ----- | ------------------------------ |
| `DATA_BITS`     | 16    | Q1.15 word width               |
| `ARRAY_SIZE`    | 4     | 4×4 FMA grid                    |
| `PIFMA_INTERVAL` | 2     | Pipeline registers every 2 FMAs |


**Ports:** `clk`, `reset`, `enable`, `clear_acc`, `load_weights`, `compute_enable`, `a_inputs_flat[63:0]` (4 × 16-bit), `b_inputs_flat[63:0]` (4 × 16-bit), `results_flat[255:0]` (16 × 16-bit), `ready`

**Architecture:** NxN FMA grid with weight-stationary dataflow. Activations flow left-to-right, partial sums flow top-to-bottom. Pipeline registers inserted every `PIFMA_INTERVAL` columns for timing closure.

---

### Macro: `core`

A complete compute core containing the scheduler pipeline, 4 threads (each with ALU/FMA/Activation/LSU/Registers/PC), 2 systolic arrays, instruction cache, memory coalescing, weight memory, and KV-cache.

**Config** (`librelane/core/config.json`):

```json
{
  "DESIGN_NAME": "core",
  "VERILOG_FILES": [
    "dir::../../src/core.sv",
    "dir::../../src/decoder.sv",
    "dir::../../src/fetcher.sv",
    "dir::../../src/scheduler.sv",
    "dir::../../src/alu.sv",
    "dir::../../src/fma.sv",
    "dir::../../src/activation.sv",
    "dir::../../src/lsu.sv",
    "dir::../../src/registers.sv",
    "dir::../../src/pc.sv",
    "dir::../../src/array.sv",
    "dir::../../src/fma.sv",
    "dir::../../src/cache.sv",
    "dir::../../src/branch_diverge.sv",
    "dir::../../src/mem_coalesce.sv",
    "dir::../../src/weight_mem.sv",
    "dir::../../src/kv_cache.sv"
  ],
  "CLOCK_PORT": "clk",
  "CLOCK_FMARIOD": 60,
  "RUN_ANTENNA_REPAIR": true
}
```

**RTL Parameters:**


| Parameter             | Value | Description               |
| --------------------- | ----- | ------------------------- |
| `THREADS_FMAR_BLOCK`   | 4     | Parallel threads          |
| `SYSTOLIC_SIZE`       | 4     | 4×4 FMA arrays             |
| `NUM_ARRAYS` | 32    | Arrays per core           |
| `CACHE_SIZE`          | 64    | Instruction cache entries |


**Ports:** `clk`, `reset`, `start`, `done`, `block_id[7:0]`, `thread_count`, program memory interface (single channel), flattened data memory interface (4 thread channels)

**Contains:** 17 source modules — full scheduler pipeline, per-thread compute units, 2 systolic arrays (32 FMAs), memory coalescing, weight banks, and KV-cache.

---

### Macro: `gpu`

The top-level design integrating 1 core, memory controllers, dispatcher, and DCR.

**Config** (`librelane/gpu/config.json`):

See `librelane/gpu/config.json` for the full configuration. Key settings:

```json
{
  "DESIGN_NAME": "gpu",
  "CLOCK_PORT": "clk",
  "CLOCK_FMARIOD": 60,
  "RUN_ANTENNA_REPAIR": true,
  "DRT_ANTENNA_REPAIR_ITERS": 10,
  "DRT_ANTENNA_REPAIR_MARGIN": 20,
  "GRT_ANTENNA_REPAIR_ITERS": 10,
  "GRT_ANTENNA_REPAIR_MARGIN": 20,
  "FP_CORE_UTIL": 40,
  "PL_TIMING_DRIVEN": true,
  "PL_ROUTABILITY_DRIVEN": true
}
```

**RTL Parameters:**


| Parameter                  | Value | Description             |
| -------------------------- | ----- | ----------------------- |
| `NUM_CORES`                | 1     | Parallel compute cores  |
| `THREADS_FMAR_BLOCK`        | 4     | Threads per block       |
| `DATA_MEM_NUM_CHANNELS`    | 4     | Data memory channels    |
| `PROGRAM_MEM_NUM_CHANNELS` | 1     | Program memory channels |
| `SYSTOLIC_SIZE`            | 2     | 2×2 FMA grid             |
| `NUM_ARRAYS`      | 2     | Arrays per core         |


**Key physical design settings:**

- **40% core utilization** — tighter packing for shorter wires and fewer antenna violations
- **Timing-driven placement** — `PL_TIMING_DRIVEN` and `PL_ROUTABILITY_DRIVEN` enabled
- **Aggressive antenna repair** — 10 iterations with 20% safety margin for both GRT and DRT
- **Target: Artix-7 FPGA** — sized to fit XC7A100T with comfortable margin

**Contains:** All 21 source modules — 1 core (8 total FMAs), 2 memory controllers (1 program, 1 data), dispatcher, and DCR.

---

## Output Files

Each macro produces:

```
runs/<run_id>/results/final/
├── gds/          # GDSII layout
├── lef/          # Library Exchange Format (for macro integration)
├── def/          # Design Exchange Format
├── sdc/          # Timing constraints
└── reports/      # Synthesis, placement, CTS, routing reports
```

Final GPU GDS:

```
librelane/gpu/runs/<run_id>/results/final/gds/gpu.gds
```

Pre-built GDS files are available in `gds/atreides_v3/`:

```
gds/atreides_v3/
├── fma.gds
├── array.gds
├── core.gds
└── gpu.gds
```

---

## Viewing the Layout

GDS Render

```bash
# Using KLayout
klayout librelane/gpu/runs/<run_id>/results/final/gds/gpu.gds

# Or view pre-built GDS
make view_layout

# Using Magic
magic -T $PDK_ROOT/sky130A/libs.tech/magic/sky130A.tech \
  librelane/gpu/runs/<run_id>/results/final/gds/gpu.gds
```

---

## Design Metrics


| Metric           | Value                   |
| ---------------- | ----------------------- |
| Technology       | SkyWater 130nm          |
| Clock (GPU top)  | 125 MHz (8 ns period)   |
| Clock (FMA)       | 200 MHz (5 ns period)   |
| Core Utilization | 40% (GPU top-level)     |
| Total FMAs        | 1024                    |
| Target FPGA      | Xilinx Artix-7          |
| DRC              | Clean                   |
| LVS              | Clean                   |
| Antenna          | Clean                   |


---

# Modules


| Module         | File                | Description                                                   |
| -------------- | ------------------- | ------------------------------------------------------------- |
| GPU Top        | `gpu.sv`            | Top-level GPU: cores, controllers, dispatcher, DCR            |
| Core           | `core.sv`           | Compute core: scheduler, threads, systolic arrays, subsystems |
| ALU            | `alu.sv`            | Integer arithmetic (ADD, SUB, MUL, DIV, CMP)                  |
| FMA            | `fma.sv`            | Q1.15 fused multiply-add (2-cycle pipelined)                  |
| Activation     | `activation.sv`     | Bias + activation (ReLU, LeakyReLU, ClippedReLU)              |
| Decoder        | `decoder.sv`        | 16-bit instruction decoder (12 opcodes)                       |
| Registers      | `registers.sv`      | 16-register file (13 R/W + 3 read-only)                       |
| LSU            | `lsu.sv`            | Load-store unit (async FSM)                                   |
| PC             | `pc.sv`             | Program counter (NZP branch, imm9 target)                     |
| Scheduler      | `scheduler.sv`      | 7-state core pipeline FSM                                     |
| Fetcher        | `fetcher.sv`        | Async instruction fetcher                                     |
| Dispatcher     | `dispatch.sv`       | Thread block dispatcher                                       |
| DCR            | `dcr.sv`            | Device control register                                       |
| Controller     | `controller.sv`     | Memory controller (priority round-robin)                      |
| Cache          | `cache.sv`          | Direct-mapped instruction cache (64 entries)                  |
| Systolic FMA    | `fma.sv`    | 3-stage pipelined Q1.15 MAC                                   |
| Systolic Array | `array.sv` | NxN weight-stationary FMA array                                |
| Pipeline       | `pipeline.sv`       | 5-stage instruction pipeline                                  |
| Branch Diverge | `branch_diverge.sv` | SIMT branch divergence with stack                             |
| Mem Coalesce   | `mem_coalesce.sv`   | Memory request coalescing                                     |
| Weight Mem     | `weight_mem.sv`     | Weight/activation banks (4 banks, double-buffered)            |
| KV Cache       | `kv_cache.sv`       | Transformer KV-cache (4 heads, sliding window)                |


---



**Atreides v3.0** — *Superfloat Project*
