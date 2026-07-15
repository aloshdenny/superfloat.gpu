<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

**Atreides** is a Q1.15 fixed-point neural network accelerator GPU implemented in SystemVerilog, designed for on-chip neural network inference on the SkyWater 130nm process.

### Architecture

- **2 Compute Cores**, each with 4 threads per block and 2 systolic arrays of 2×2 FMA grids (8 FMAs per core, 16 total)
- **Q1.15 Fixed-Point Arithmetic** — bounded `[-1, 1]` range optimised for normalised neural network weights and activations
- **Instruction Cache** — 2-entry per-core cache for program memory
- **KV-Cache** — Native hardware support for transformer attention patterns
- **Memory Coalescing** — Efficient tensor memory access patterns
- **8 data + 2 program** external memory channels, time-multiplexed over the bidirectional I/O bus

### External Memory Interface

The GPU offloads program and data memory to an external SRAM (e.g. a 23LC1024 connected to the TinyTapeout demo board). The `uio[7:0]` bidirectional bus carries a time-multiplexed address/data protocol:

1. **Address Phase (3 cycles):** `ui_in[7]` (ALE) goes HIGH; lower byte, middle byte, then upper byte + control flags are driven on `uio`.
2. **Data Phase (2 cycles):** For writes, data bytes are driven. For reads, `uio_oe` drops LOW and data is sampled from the external SRAM.
3. **Acknowledge:** GPU memory channel is signalled complete.

### Execution Model

1. Load kernel into external program memory.
2. Load weights/activations into external data memory (Q1.15 format).
3. Write `thread_count` to `ui_in[6:0]` with `ui_in[7]` LOW to configure the device.
4. Pulse `ui_in[7]` HIGH to start execution.
5. Poll `uo_out[0]` (GPU done) to detect completion.

## How to test

1. Connect an external SPI/parallel SRAM to the `uio[7:0]` bus, `uo_out[1]` (WE), `uo_out[2]` (RE), `uo_out[3]` (ALE), `uo_out[4]` (MEM_SEL).
2. Pre-load the SRAM with a compiled matrix-multiply kernel and Q1.15 input data.
3. Set clock to 50 MHz or below.
4. Assert `rst_n` LOW then HIGH to reset.
5. Write thread count to `ui_in[6:0]`, then pulse `ui_in[7]` HIGH to start.
6. Wait for `uo_out[0]` to go HIGH indicating completion.
7. Read results back from data memory via the bus.

Simulation traces and test kernels are available in the project repository's `test/` directory.

## External hardware

- **External SRAM** (e.g. 23LC1024 or equivalent) connected to the `uio[7:0]` bidirectional bus.
- TinyTapeout demo board RP2040 microcontroller can act as the memory controller, servicing SRAM read/write requests from the GPU's external memory interface.
