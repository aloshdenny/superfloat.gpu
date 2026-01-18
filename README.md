# Atreides

<div align="center">

**Superfloat's Atreides: A Q1.15 Fixed-Point Neural Network Accelerator**

</div>

---

A minimal GPU implementation in SystemVerilog optimized for neural network inference with Q1.15 fixed-point arithmetic, systolic arrays, and LLM-specific optimizations.

Built with fully documented SystemVerilog, complete documentation on architecture & ISA, working matrix addition/multiplication kernels with FMA support, and full support for kernel simulation & execution traces.

### Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [GPU](#gpu)
  - [Memory](#memory)
  - [Core](#core)
  - [Systolic Array](#systolic-array)
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
- [ASIC Generation (OpenLane)](#asic-generation-openlane)

# Overview

**Atreides** is a neural network accelerator designed from the ground up for efficient fixed-point inference. Unlike traditional GPUs that focus on floating-point graphics, Atreides is optimized for the specific computational patterns found in modern deep learning:

- **Q1.15 Fixed-Point Arithmetic** - Bounded [-1, 1] range perfect for normalized weights and activations
- **Fused Multiply-Add (FMA)** - Single-cycle MAC operations with higher internal precision
- **Systolic Arrays** - Hardware matrix multiplication acceleration
- **KV-Cache** - Native support for transformer attention mechanisms
- **Memory Coalescing** - Efficient memory access patterns for tensor operations

## Design Philosophy

Atreides follows the principle of **separation of concerns**:

- **Integer arithmetic** (ADD, SUB, MUL, DIV) for indexing, addressing, and control flow
- **Q1.15 fixed-point** (FMA) exclusively for neural network computations

This separation allows optimal hardware for each use case while maintaining a simple, understandable architecture.

# Architecture

<p float="left">
  <img src="/docs/images/gpu.png" alt="GPU" width="48%">
  <img src="/docs/images/core.png" alt="Core" width="48%">
</p>

## GPU

Atreides executes a single kernel at a time with the following launch sequence:

1. Load global program memory with the kernel code
2. Load data memory with the necessary data (weights, activations in Q1.15)
3. Specify the number of threads to launch in the device control register
4. Launch the kernel by setting the start signal to high

The GPU consists of:

| Unit | Description |
|------|-------------|
| Device Control Register | Stores kernel execution metadata |
| Dispatcher | Distributes threads to compute cores |
| Compute Cores | Variable number of parallel processing units |
| Memory Controllers | Manage data & program memory access |
| Instruction Cache | Reduces program memory latency |
| Memory Coalescing Unit | Combines sequential memory requests |
| Weight/Activation Banks | Dedicated neural network memory |
| KV-Cache | Transformer attention key/value storage |

### Device Control Register

Stores the `thread_count` - the total number of threads to launch for the active kernel.

### Dispatcher

Manages distribution of threads to compute cores, organizing threads into **blocks** that execute in parallel on a single core.

## Memory

### Global Memory Specifications

| Memory Type | Address Bits | Data Bits | Description |
|-------------|--------------|-----------|-------------|
| Data Memory | 8 bits (256 rows) | 16 bits (Q1.15) | Stores weights, activations, results |
| Program Memory | 8 bits (256 rows) | 16 bits | Kernel instructions |

### Memory Controllers

Handle throttling of memory requests based on external bandwidth and relay responses back to compute cores. Each controller has configurable channels based on memory bandwidth.

### Instruction Cache

```
┌─────────────────────────────────────────┐
│           INSTRUCTION CACHE             │
├─────────────────────────────────────────┤
│  TAG  │  VALID  │  INSTRUCTION DATA     │
├───────┼─────────┼───────────────────────┤
│ 4-bit │  1-bit  │      16-bit           │
└───────┴─────────┴───────────────────────┘
```

Direct-mapped cache that stores recently fetched instructions, reducing program memory access latency.

## Core

Each core processes one **block** at a time with dedicated resources per thread:

| Resource | Per Thread | Description |
|----------|------------|-------------|
| ALU | Yes | Integer arithmetic (ADD, SUB, MUL, DIV) |
| FMA | Yes | Q1.15 fused multiply-add |
| LSU | Yes | Load-store unit for memory access |
| PC | Yes | Program counter |
| Register File | Yes | 16 registers (13 R/W + 3 read-only) |

### Scheduler

Manages thread execution with support for:
- Sequential instruction execution
- Pipelining for improved throughput
- Warp scheduling for latency hiding

### Fetcher

Asynchronously fetches instructions from program memory/cache at the current PC.

### Decoder

Decodes 16-bit instructions into control signals:

```
┌────────┬────────┬────────┬────────┐
│ OPCODE │   Rd   │   Rs   │   Rt   │
│ [15:12]│ [11:8] │  [7:4] │  [3:0] │
└────────┴────────┴────────┴────────┘
```

## Systolic Array

Atreides includes a configurable NxN systolic array for accelerated matrix multiplication:

```
        ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐
  a[0]──│ PE  │───│ PE  │───│ PE  │───│ PE  │──▶
        │ 0,0 │   │ 0,1 │   │ 0,2 │   │ 0,3 │
        └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
           │         │         │         │
        ┌──▼──┐   ┌──▼──┐   ┌──▼──┐   ┌──▼──┐
  a[1]──│ PE  │───│ PE  │───│ PE  │───│ PE  │──▶
        │ 1,0 │   │ 1,1 │   │ 1,2 │   │ 1,3 │
        └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
           │         │         │         │
        ┌──▼──┐   ┌──▼──┐   ┌──▼──┐   ┌──▼──┐
  a[2]──│ PE  │───│ PE  │───│ PE  │───│ PE  │──▶
        │ 2,0 │   │ 2,1 │   │ 2,2 │   │ 2,3 │
        └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
           │         │         │         │
        ┌──▼──┐   ┌──▼──┐   ┌──▼──┐   ┌──▼──┐
  a[3]──│ PE  │───│ PE  │───│ PE  │───│ PE  │──▶
        │ 3,0 │   │ 3,1 │   │ 3,2 │   │ 3,3 │
        └──┬──┘   └──┬──┘   └──┬──┘   └──┬──┘
           ▼         ▼         ▼         ▼
         b[0]      b[1]      b[2]      b[3]
```

Each Processing Element (PE) performs Q1.15 multiply-accumulate operations.

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

| Property | Value |
|----------|-------|
| Total Bits | 16 |
| Sign Bits | 1 |
| Fractional Bits | 15 |
| Range | [-1.0, +0.999969...] |
| Resolution | 2^-15 ≈ 0.0000305 |

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

1. **Normalized Range** - Neural network weights and activations are typically normalized to [-1, 1]
2. **Efficient Multiplication** - 15×15 bit multiplication fits in 30 bits
3. **No Overflow in Accumulation** - Using 32-bit accumulators prevents overflow
4. **Hardware Efficient** - Simpler than floating-point, lower power consumption

# ISA

![ISA](/docs/images/isa.png)

Atreides implements a 12-instruction ISA optimized for neural network kernels:

| Opcode | Mnemonic | Format | Description |
|--------|----------|--------|-------------|
| 0000 | NOP | - | No operation |
| 0001 | BRnzp | nzp, imm | Branch on condition |
| 0010 | CMP | Rd, Rs | Compare (sets NZP flags) |
| 0011 | ADD | Rd, Rs, Rt | Integer add (indexing) |
| 0100 | SUB | Rd, Rs, Rt | Integer subtract (indexing) |
| 0101 | MUL | Rd, Rs, Rt | Integer multiply (indexing) |
| 0110 | DIV | Rd, Rs, Rt | Integer divide (indexing) |
| 0111 | LDR | Rd, Rs | Load 16-bit from memory |
| 1000 | STR | Rd, Rs | Store 16-bit to memory |
| 1001 | CONST | Rd, imm | Load 8-bit immediate (sign-extended) |
| **1010** | **FMA** | **Rd, Rs, Rt** | **Q1.15 fused multiply-add: Rd = (Rs × Rt) + Rd** |
| 1111 | RET | - | End thread execution |

### Key Design Decision

- **Integer operations** (ADD, SUB, MUL, DIV): Used for indexing, addressing, loop counters
- **FMA operation**: Used exclusively for Q1.15 matrix computations

This separation ensures optimal hardware for each use case.

### Register Map

| Register | Name | Description |
|----------|------|-------------|
| R0-R12 | General | Read/write registers |
| R13 | %blockIdx | Block index (read-only) |
| R14 | %blockDim | Block dimension (read-only) |
| R15 | %threadIdx | Thread index (read-only) |

# Execution

### Core Control Flow

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│  FETCH  │───▶│ DECODE  │───▶│ REQUEST │───▶│  WAIT   │───▶│ EXECUTE │───▶│ UPDATE  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘
```

1. **FETCH** - Fetch instruction from cache/program memory
2. **DECODE** - Decode into control signals
3. **REQUEST** - Request memory if LDR/STR
4. **WAIT** - Wait for memory response
5. **EXECUTE** - Execute ALU/FMA computation
6. **UPDATE** - Write back to registers

### Thread

![Thread](/docs/images/thread.png)

Each thread has dedicated ALU, FMA, LSU, PC, and register file. The `%blockIdx`, `%blockDim`, and `%threadIdx` registers enable SIMD functionality.

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
- **Hazard Detection** - RAW hazard detection and stalling
- **Data Forwarding** - Forward results from EX/MEM stages
- **Load-Use Stall** - Automatic stall for load-use hazards

# Neural Network Features

## FMA Unit

The Fused Multiply-Add unit is optimized for Q1.15 neural network computations:

```
┌─────────────────────────────────────────────────────────────┐
│                          FMA UNIT                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────┐    ┌─────┐                                        │
│   │ R1  │    │ R2  │   Input Registers                      │
│   │ Act │    │ Wgt │                                        │
│   └──┬──┘    └──┬──┘                                        │
│      │          │                                           │
│      ▼          ▼                                           │
│   ┌──────────────────┐                                      │
│   │   Sign XOR       │  sign_out = sign_a ^ sign_w          │
│   └────────┬─────────┘                                      │
│            │                                                │
│   ┌────────▼─────────┐                                      │
│   │  15×15 Multiply  │  mantissa_a × mantissa_w             │
│   │   (30-bit out)   │                                      │
│   └────────┬─────────┘                                      │
│            │                                                │
│   ┌────────▼─────────┐                                      │
│   │    R3: Product   │  Weighted input                      │
│   └────────┬─────────┘                                      │
│            │                                                │
│   ┌────────▼─────────┐    ┌─────┐                           │
│   │   Accumulate     │◀───│ R4  │  Running sum              │
│   │   (32-bit)       │    │ Acc │                           │
│   └────────┬─────────┘    └─────┘                           │
│            │                                                │
│   ┌────────▼─────────┐    ┌─────┐                           │
│   │   Add Bias       │◀───│ R5  │  Bias term                │
│   └────────┬─────────┘    │Bias │                           │
│            │              └─────┘                           │
│   ┌────────▼─────────┐                                      │
│   │  ReLU Activation │  max(0, x)                           │
│   └────────┬─────────┘                                      │
│            │                                                │
│            ▼                                                │
│       Output (Q1.15)                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Key optimizations:
- **Sign-magnitude multiplication** - XOR for sign, 15×15 for mantissa
- **32-bit accumulator** - Prevents overflow during dot products
- **Integrated bias & activation** - Single-pass computation
- **Pipelined registers** (R1-R5) - High throughput

## Systolic Array

Hardware-accelerated matrix multiplication with configurable NxN PE array:

```systemverilog
module systolic_pe #(
    parameter DATA_BITS = 16
) (
    input wire clk, reset, enable,
    input wire [DATA_BITS-1:0] a_in,      // Activation from left
    input wire [DATA_BITS-1:0] b_in,      // Weight from top
    output reg [DATA_BITS-1:0] a_out,     // Pass activation right
    output reg [DATA_BITS-1:0] b_out,     // Pass weight down
    output reg [DATA_BITS-1:0] result     // Accumulated result
);
```

Each PE performs: `result += a_in × b_in` (in Q1.15)

## KV-Cache

Native support for transformer attention with sliding window:

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
│  • Sliding window attention support                         │
│  • Batch read for attention computation                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Parameters:
- `NUM_HEADS`: 4 (configurable)
- `HEAD_DIM`: 16 (configurable)
- `MAX_SEQ_LEN`: 256 (configurable)

## Weight & Activation Memory

Dedicated memory banks with double-buffering for neural network inference:

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
│  • 1024 entries per bank (1K × 16-bit = 16KB per bank)      │
│  • Prefetch support for hiding latency                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

# Advanced Features

## Memory Coalescing

Combines multiple sequential memory requests into single transactions:

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
1. Analyzes pending memory requests
2. Identifies sequential addresses
3. Combines into single wide transaction
4. Distributes results back to threads

## Branch Divergence

Handles SIMT execution when threads take different paths:

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
- **Divergence Stack** - Tracks divergent thread masks
- **Warp Mask** - Active thread tracking per warp
- **Reconvergence Detection** - Automatic at post-dominator points
- **Nested Divergence** - Stack-based handling of nested branches

## Instruction Pipeline

5-stage pipeline with hazard handling:

| Stage | Description | Hazard Handling |
|-------|-------------|-----------------|
| IF | Instruction Fetch | - |
| ID | Instruction Decode | RAW detection |
| EX | Execute (ALU/FMA) | Data forwarding |
| MEM | Memory Access | Load-use stall |
| WB | Write Back | - |

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

# Clean build artifacts
make clean
```

### Output

Simulation produces log files in `test/logs/` with:
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

# Test Files

The test infrastructure provides comprehensive simulation and verification:

```
test/
├── __init__.py              # Test package marker
├── tb_gpu.sv                # Testbench with memory models
├── test_matadd.py           # Matrix addition kernel test
├── test_matmul.py           # Matrix multiplication kernel test
├── helpers/
│   ├── __init__.py          # Helper package exports
│   ├── q115.py              # Q1.15 fixed-point conversion utilities
│   ├── format.py            # Trace formatting (decode instructions)
│   ├── logger.py            # File/console logging with timestamps
│   ├── memory.py            # Memory init & assembly instruction helpers
│   └── setup.py             # Test setup, kernel execution, state capture
└── logs/
    ├── matadd_latest.log    # Latest matadd test output
    └── matmul_latest.log    # Latest matmul test output
```

### Test Helper Modules

| Module | Description |
|--------|-------------|
| `q115.py` | Q1.15 ↔ float conversion, Q1.15 arithmetic (mul, add, fma) |
| `format.py` | Instruction decoding, register formatting, trace output |
| `logger.py` | `GPULogger` class for trace files with timestamps |
| `memory.py` | Memory init, assembly helpers (`asm_add`, `asm_fma`, etc.) |
| `setup.py` | `setup_test()`, `run_kernel()`, `get_core_states()` |

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

# ASIC Generation (OpenLane)

Atreides can be synthesized to a physical GDSII layout using the OpenLane ASIC flow targeting the SkyWater 130nm process.

### Prerequisites

```bash
# Install OpenLane (Docker-based)
git clone https://github.com/The-OpenROAD-Project/OpenLane.git ~/OpenLane
cd ~/OpenLane
make

# Install PDK
make pdk

# Install sv2v (SystemVerilog to Verilog converter)
brew install sv2v
```

### Setup Design Directory

```bash
# Create design directory
mkdir -p ~/OpenLane/designs/atreides/src
mkdir -p ~/OpenLane/designs/atreides/src_v

# Copy SystemVerilog sources
cp src/*.sv ~/OpenLane/designs/atreides/src/

# Convert SystemVerilog to Verilog (required for Yosys)
cd ~/OpenLane/designs/atreides
sv2v src/*.sv -w src_v/
```

### Configuration

Create `~/OpenLane/designs/atreides/config.json`:

```json
{
    "DESIGN_NAME": "gpu",
    "VERILOG_FILES": "dir::src_v/*.v",
    "CLOCK_PORT": "clk",
    "CLOCK_PERIOD": 40.0,
    "FP_SIZING": "absolute",
    "DIE_AREA": "0 0 2200 2200",
    "FP_CORE_UTIL": 30,
    "PL_TARGET_DENSITY": 0.35,
    "GRT_ADJUSTMENT": 0.15,
    "ROUTING_CORES": 4,
    "RUN_CVC": false,
    "GRT_REPAIR_ANTENNAS": true,
    "DIODE_ON_PORTS": "in",
    "RUN_HEURISTIC_DIODE_INSERTION": true,
    "FP_PDN_CHECK_NODES": false,
    "RUN_KLAYOUT_XOR": false,
    "RUN_KLAYOUT_DRC": false,
    "MAX_FANOUT_CONSTRAINT": 8,
    "RUN_LINTER": false,
    "SYNTH_STRATEGY": "DELAY 0",
    "PL_RESIZER_DESIGN_OPTIMIZATIONS": true,
    "PL_RESIZER_TIMING_OPTIMIZATIONS": true,
    "GLB_RESIZER_TIMING_OPTIMIZATIONS": true,
    "pdk::sky130*": {
        "CLOCK_PERIOD": 40.0
    }
}
```

### Run OpenLane Flow

```bash
cd ~/OpenLane

# Run the full RTL-to-GDSII flow
docker run --rm \
  -v ~/OpenLane:/openlane \
  -v ~/OpenLane/designs:/openlane/install \
  -v ~/.ciel:/.ciel \
  -e PDK_ROOT=/.ciel \
  -e PDK=sky130A \
  -e PWD=/openlane \
  ghcr.io/the-openroad-project/openlane:latest \
  ./flow.tcl -design atreides
```

Or interactively:

```bash
cd ~/OpenLane
make mount

# Inside Docker container:
./flow.tcl -design atreides
```

### Output Files

After successful completion, find outputs at:

```
~/OpenLane/designs/atreides/runs/<run_id>/results/final/
├── gds/
│   └── gpu.gds          # Final GDSII layout
├── lef/
│   └── gpu.lef          # Library Exchange Format
├── def/
│   └── gpu.def          # Design Exchange Format
├── verilog/
│   └── gpu.v            # Gate-level netlist
└── sdc/
    └── gpu.sdc          # Timing constraints
```

### Design Metrics

| Metric | Value |
|--------|-------|
| Technology | SkyWater 130nm |
| Clock Frequency | 25 MHz (40ns period) |
| Die Area | ~4.84 mm² |
| Core Utilization | 30% |
| Cell Count | ~58,000 |
| Wire Length | ~3.6 km |
| DRC | Clean |
| LVS | Clean |

### Viewing the Layout

```bash
# Using KLayout
klayout ~/OpenLane/designs/atreides/runs/<run_id>/results/final/gds/gpu.gds

# Using Magic
magic -T ~/.ciel/sky130A/libs.tech/magic/sky130A.tech \
  ~/OpenLane/designs/atreides/runs/<run_id>/results/final/gds/gpu.gds
```

# Module Summary

| Module | File | Description |
|--------|------|-------------|
| GPU Top | `gpu.sv` | Top-level GPU module |
| Core | `core.sv` | Compute core with ALU, FMA, LSU |
| ALU | `alu.sv` | Integer arithmetic unit |
| FMA | `fma.sv` | Q1.15 fused multiply-add |
| Decoder | `decoder.sv` | Instruction decoder |
| Registers | `registers.sv` | Register file (16-bit) |
| LSU | `lsu.sv` | Load-store unit |
| PC | `pc.sv` | Program counter |
| Scheduler | `scheduler.sv` | Thread scheduler |
| Fetcher | `fetcher.sv` | Instruction fetcher |
| Dispatcher | `dispatch.sv` | Thread dispatcher |
| DCR | `dcr.sv` | Device control register |
| Controller | `controller.sv` | Memory controller |
| Cache | `cache.sv` | Instruction cache |
| Systolic PE | `systolic_pe.sv` | Processing element |
| Systolic Array | `systolic_array.sv` | NxN PE array |
| Activation | `activation.sv` | Bias & activation unit |
| Pipeline | `pipeline.sv` | 5-stage instruction pipeline |
| Branch Diverge | `branch_diverge.sv` | Branch divergence handling |
| Mem Coalesce | `mem_coalesce.sv` | Memory coalescing unit |
| Weight Mem | `weight_mem.sv` | Weight/activation banks |
| KV Cache | `kv_cache.sv` | Transformer KV cache |

---

<div align="center">

**Atreides** - *Fear is the mind-killer.*

Built for learning. Built for inference. Built for the future.

</div>
