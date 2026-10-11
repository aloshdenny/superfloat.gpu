# SuperFloat tiles in a HammerBlade pod: compiler and runtime reference

For whoever builds the LLVM/Clang toolchain and the lowering. **Source of truth:** `superfloat.gpu`, branch `hammerblade` (head `b424cb0`). Paths are relative to the repository root and `file:line` cites that commit.

**Upstream is not in this checkout.** The upstream `bsg_manycore` sources (endpoint, `eva_to_npa`, `bsg_manycore.h`, the build system) are pinned to bsg_manycore `0052ce8`, basejump_stl `3753148` and Verilator `983a06a` (`hb/results/versions.txt`). Anything marked **[upstream]** below is described as our RTL and drivers use it. Check it in those sources before relying on it.

**SF16 encoding differs from the v3 RV64 chip.** These tiles store SF16 as sign-magnitude Q1.15 in memory, as the measured matrix units take it. The v3 chip's RV64 ISA (`docs/v3_isa.md` on branches `gt2n`, `gt3`, `nangate45`) stores SF16 in two's complement and converts at the matrix-unit inputs, so standard RISC-V vector instructions work on it. Both round half to even on the magnitude and never produce `0x8000`. A compiler targeting both must convert at this boundary.

---

## 1. The pod, and who runs what

**One 4 × 2 pod** (`hb/machines/*/Makefile.machine.include:4-5`):

- **Row 0:** four vanilla RISC-V cores.
- **Row 1:** four SuperFloat tiles, all of one format and kind.
- **Memory:** 8 vcaches (64 sets × 4 ways × 8-word lines = 64 KB in all, `:15-19`) sit in front of a 2 GiB DRAM model (`:23`, `e_vcache_test_mem` at `:38`).

**How the tile row gets its type.** Each machine places its tiles with `SF_MACHINE_DEFINES = +define+SF_ACCEL_ROW=1 +define+SF_ACCEL_TYPE=<n>` (`:48`). `hb/setup_pod.sh:18-26` patches upstream's tile array so that row `SF_ACCEL_ROW` takes type `SF_ACCEL_TYPE`.

| Machine | Socket type (`hb/v/bsg_manycore_hetero_socket.sv:128-147`) | Tile | NA | MUL_ST | IPOLY hashing | Results in `hb/results/` |
|---|---|---|---|---|---|---|
| `sf_4x2_{sf16,fp16,bf16}` | 9 / 10 / 11 | v1, direct adapter | – | – | 0 | `<fmt>.jsonl` |
| `sf_4x2_*_rb` | 12 / 13 / 14 | v1, 8-line read buffer | – | – | 0 | `<fmt>_rb.jsonl` |
| `v3_4x2_{sf16,fp16,bf16}` | 15 / 16 / 17 | v3 | 8 | 1 | 0 | `v3_<fmt>.jsonl` |
| `v3_4x2_*_m2` | 18 / 19 / 20 | v3 | 8 | 2 | 0 | none |
| `v3_4x2_*_a4` | 21 / 22 / 23 | v3 | 4 | 1 | 0 | none |
| `v3i_4x2_*_m2` | 18 / 19 / 20 | v3 | 8 | 2 | 1 | `v3i_<fmt>_m2.jsonl` |
| `v3i_4x2_*_m2a4` | 24 / 25 / 26 | v3 | 4 | 2 | 1 | `v3i_<fmt>_m2a4.jsonl` |

**Who runs what:**

- **Vanilla cores run all code:** the driver, the runtime and the host operations. Toolchain: upstream's RISC-V GCC from `bsg_manycore/software/riscv-tools` (`hb/README.md:52`); see §5 and §6.
  - In our runs only core (0,0) does anything. The driver Makefiles set `bsg_tiles_X = bsg_tiles_Y = 1` (`hb/sw/v3/Makefile:4-5`), and `main` parks every other core (`hb/sw/v3/main.c:28-29`).
  - The FP32 baseline uses all four cores (`hb/sw/vanilla/Makefile:4-5`).
- **The SuperFloat tiles run no RISC-V code.** Each is a memory-mapped device behind upstream's `bsg_manycore_endpoint_standard` (`hb/v/sf_hb_accel.sv:123-169`, `hb/v/sf_hb_v3.sv:131-148`).
  - **v1** runs a 16-bit v1 program that the driver uploads into it.
  - **v3** has no instruction stream. It is driven by a descriptor written as CSRs.
- **Neither tile joins the hardware barrier.** Both tie its outputs to 0 (`sf_hb_accel.sv:95-97`, `sf_hb_v3.sv:91-93`).

### 1.1 Addressing a tile from a vanilla core

Both drivers wrap upstream's global-pod macros [upstream: EVA encoding]:

```c
#define ACC_Y  1                               // the tile row
#define CSR(i) ((0x2000 + (i)) << 2)          // byte offset of CSR i
#define PMEM(i) ((i) << 2)                    // v1 only: byte offset of program word i
acc_store(t, addr, v) = bsg_global_pod_store(0, 0, t, ACC_Y, addr, v);   // t = tile column 0..3
acc_load (t, addr)    = bsg_global_pod_load (0, 0, t, ACC_Y, addr, v);
```

(`hb/sw/main.c:19-21,39-40`; `hb/sw/v3/main.c:15-16,23-24`.)

**What the tile sees.** The tile receives the word EPA `in_addr` (byte offset / 4). Every request is accepted at once and answered the next cycle (`in_yumi = in_v`; `sf_hb_accel.sv:185,219-220`; `sf_hb_v3.sv:164,188-189`). A load returns the CSR value. A store returns 0.

**Decoding quirks** that matter to a lowering:

- **CSR space.** A CSR is any EPA with bit 13 set and nothing above bit 13 (`sf_hb_accel.sv:180`, `sf_hb_v3.sv:160`).
  - The select is only `addr[3:0]` (v1) or `addr[4:0]` (v3), and the bits in between are ignored. So CSRs alias every 16 (v1) or 32 (v3) words. Use the exact addresses.
- **Byte masks are ignored on CSR and program writes.** Always use 32-bit `sw` with the value in bits [31:0].
- **Writes to undecoded addresses** are acknowledged and dropped. Reads of them return 0 (`sf_hb_accel.sv:41`).

### 1.2 Launch and completion (both tiles)

**To launch:**

1. Write the descriptor CSRs.
2. Write `DONE_ADDR`: the word EPA of a flag in the launching core's own data memory. Both drivers pass `((int)&done_flag[t]) >> 2`, where `done_flag` is a `static volatile int` in DMEM (`hb/sw/v3/main.c:21,50`) [upstream: why a DMEM pointer >> 2 is that tile's EPA].
3. Clear the flag.
4. Write `START`.

**What the tile does:**

1. Latches the START packet's source coordinates (`sf_hb_accel.sv:619-620`, `sf_hb_v3.sv:498-499`).
2. Runs the launch.
3. Waits until every store it issued is acknowledged (credits back to 0).
4. Sends one remote store: payload `1`, mask `1111`, to (`caller_x`, `caller_y`, `DONE_ADDR`) (`sf_hb_accel.sv:376-382,626-631`, `sf_hb_v3.sv:304-310,507-509`).

**Consequences:**

- **Completion goes to whichever core wrote START**, so any vanilla core can own any tile.
- **When the flag reads 1, every result store has been acknowledged by its vcache.** A load of the results through the same EVA then sees them; no flush is needed inside the pod. A host outside the pod reading DRAM directly would need upstream's vcache flush, which we never use.
- **Polling, not interrupts.** The drivers spin on the local DMEM flag (`hb/sw/main.c:67-75`, `hb/sw/v3/main.c:55-56`), which costs no network traffic. The alternative is a remote load of `STATUS` bit 0, which is a network round trip.
  - Our tiles never send an interrupt. Whether the vanilla core could take one is [upstream].
- **Clear the flag before START, never after.** Both drivers do (`hb/sw/main.c:44-45`, `hb/sw/v3/main.c:51-52`).
- **Ordering of the descriptor stores.** Neither driver fences between the CSR stores and START.
  - They rely on stores from one core to one tile arriving in order, which I infer from deterministic routing; 708 launches passed this way.
  - If the core itself wrote operands into DRAM, call `bsg_fence()` before START. Those stores travel to other destinations (the vcaches), and only the fence waits for their acknowledgements. Inference [upstream: network ordering, `bsg_fence` semantics].

---

## 2. v1 tile (`hb/v/sf_hb_accel.sv`)

The tile is one unchanged v1 `core_tile` (8 threads, an 8 × 8 array) with a 32-entry instruction cache (`:247-260`) in front of a 512 × 16-bit program memory. Its data path goes to DRAM over the mesh (`:284-312`). The module's own header comment is a good summary (`:3-41`).

### 2.1 Address map (word EPA; byte offset = EPA × 4)

| EPA | Byte offset | Name | Access | Meaning |
|---|---|---|---|---|
| `0x000-0x1FF` | `0x0000-0x07FC` | PMEM[i] | write | one v1 instruction in `data[15:0]` (`:229-231`) |
| `0x2000` | `0x8000` | BASE | r/w | byte EVA of tile word 0 (`:222`) |
| `0x2001` | `0x8004` | DONE_ADDR | r/w | word EPA of the flag in the launching core's DMEM |
| `0x2002` | `0x8008` | START | write | `[7:0]` block id, `[11:8]` thread count (0-8) (`:616-618`) |
| `0x2003` | `0x800C` | STATUS | read | bit 0: busy |
| `0x2004` | `0x8010` | CYCLE | read | free-running cycle counter |
| `0x2005` | `0x8014` | BUSY_CYC | read | cycles with a block running |
| `0x2006` | `0x8018` | READS | read | data words the tile read |
| `0x2007` | `0x801C` | WRITES | read | data words written |
| `0x2008` | `0x8020` | FORMAT | read | 0 SF16, 1 FP16, 2 BF16 |
| `0x2009` | `0x8024` | BLOCKS | read | blocks completed |
| `0x200A` | `0x8028` | LOADS | read | remote loads sent (equals READS without the read buffer) |
| `0x200B` | `0x802C` | RB_LINES | read | read-buffer lines (0 = direct) |

The counters reset only with the pod (`:603-608`). They accumulate across launches, so take differences.

### 2.2 Program, window and dispatch

**Program upload.** One `sw` per instruction to `PMEM(i)` (`hb/sw/main.c:60`).

- Any program write flushes the instruction cache (`:235-237`).
- Program memory cannot be read back.
- The kernels come from `test/gpt2/kernels.py` (`gemv_program`, `gemm_program`, `:90-135`). `hb/sw/gen_launch.py:33` turns one into `prog[]`.

**Instruction encoding.** 16 bits, `[15:12]` opcode (`test/helpers/memory.py:104-221`):

| Opcode | Instruction |
|---|---|
| `0x0` | NOP |
| `0x1` | BR nzp, off9 |
| `0x2` | CMP |
| `0x3` | ADD |
| `0x4` | SUB |
| `0x5` | MUL |
| `0x6` | DIV |
| `0x7` | LDR rd, [rs] |
| `0x8` | STR [rd], rs |
| `0x9` | CONST rd, imm8 |
| `0xA` | FMA |
| `0xB` | ACT |
| `0xC` | SYS (array: clear, load, compute, read; `kernels.py:57-60`) |
| `0xF` | RET |

- R13 = `%blockIdx`, R14 = `%blockDim`, R15 = `%threadIdx`. Registers are 16 bits.
- The authoritative decoder is `src/decoder.sv`.

**Window.** Tile word address A is the halfword at byte EVA `BASE + 2A` (`:328`). The tile translates that EVA to a vcache NPA with upstream's `bsg_manycore_eva_to_npa`, using `tgo = 0` and the pod's own coordinates (`:336-359`).

- So any DRAM pointer a vanilla core uses (a `.dram` object, `0x8xxxxxxx`) is valid as BASE. The driver passes `(int) win` (`hb/sw/main.c:61`).

**Dispatch.** The vanilla core is the block scheduler (`hb/sw/main.c:65-75`):

1. Start one block per tile: `START = block | (8 << 8)`.
2. When a tile's flag rises, give it the next block.
3. Upload the program and write BASE and DONE_ADDR once per tile before the first block (`:59-63`).

**Kernel-side convention (software only).** The GPT-2 kernels read a block table at window word 0: three words per block (x base, weight base, out base). Each thread offsets by `%threadIdx` (`kernels.py:65-82`).

### 2.3 Data path

- **Direct** (`RB_LINES = 0`, `:410-447`):
  - A read is one halfword remote load (LHU, `part_sel = eva[1:0]`, `:414-415`). There is one read in flight per tile, because `core_tile` has one data channel.
  - A write is a remote store with mask `0011` or `1100` and the halfword duplicated (`:403-404`). Up to 32 stores are posted (`max_out_credits_p`, `:66,361`).
- **Read buffer** (`RB_LINES = 8`, `:448-589`):
  - It holds 8 vcache lines of 8 words, LRU.
  - A miss fetches the whole line with 8 word loads in flight, and the read is answered when its word arrives.
  - A hit is answered the next cycle and prefetches the next line.
  - Stores go to memory as in direct mode, update a held copy, and wait for an in-flight fetch of their own line (`:487-489`).
  - All lines are dropped at START (`:535`).

### 2.4 v1 constraints and pitfalls

- **Effective window: halfwords `0x0000-0xFFBF` from BASE**, although the port is 19 bits (`:100`).
  - The LSU takes the address straight from a 16-bit register (`src/lsu.sv:46-47`).
  - `0xFFC0-0xFFFF` hit a 64-halfword on-tile scratchpad and never reach DRAM (`src/scratchpad.sv:4-5,16`).
- **BASE must be even**, because masks and LHU `part_sel` assume a halfword-aligned window. `gen_launch.py:44` aligns it to 64 bytes.
- **Never write BASE, DONE_ADDR or PMEM while a tile is busy.** These writes are not gated by busy (`:221-224,229-231`), so they take effect mid-block. START while busy is dropped, with a simulation `$error` (`:616,643-644`).
- **The read buffer is not coherent across tiles within a block.** Do not read, in the same block, data another running tile or the host writes. Lines drop only at START.
- **Hot loops should fit the 32-entry instruction cache.** This is for performance only (`kernels.py:100,121`).
- **v1 is not worth targeting.** With the read buffer, a v1 tile does about one vanilla core's FP32 work (`docs/hammerblade.md:69-73`). Treat it as fixed kernels, not as a compiler target.

---

## 3. v3 matrix tile (`hb/v/sf_hb_v3.sv`)

The tile is a weight-stationary NA × NA wavefront array of v3 processing elements (`hb/v3/v3_block.sv`, `WAVE = 1`). Around the array sit:

- a DMA with 32 tags;
- NA activation banks;
- 4 weight slots;
- per-column accumulators;
- the format's pop (the single rounding to 16 bits).

### 3.1 What one launch computes

**Formula:** C[T × NC] = A[T × K] · W[K × NC], restricted to column blocks `cb ∈ [CB_START, CB_START + CB_COUNT)`. Column block `cb` is columns `[NA·cb, NA·cb + NA)` (`:14-25,604`).

- The header comment says "8 cb", but the code uses NA, so a column block is 4 columns on the `a4` tiles.

**Accumulation.** Each column block runs K/NA passes. Pass `kb` feeds the array rows with k = NA·kb + r, r = 0..NA-1, so products enter each column's sum in strict order k = 0, 1, …, K-1 (`:384-386`).

- The first pass starts from zero (`:396`).
- The partial sums stay in the accumulator format between passes (`accm`, `:212,601`).
- The last pass goes through the pop and is stored, two values per 32-bit word (`:600-609`).

**What the tile does not do:** accumulate into an existing C, add a bias, apply an activation, transpose, or reduce across tiles.

### 3.2 Descriptor: the CSR map (word EPA `0x2000 + i`, byte offset `0x8000 + 4i`; all 32-bit)

| i | Byte offset | Name | Access | Meaning and constraints |
|---|---|---|---|---|
| 0 | `0x8000` | A_BASE | r/w | byte EVA of A, row-major T × K halfwords; 4-byte aligned |
| 1 | `0x8004` | W_BASE | r/w | byte EVA of tile (cb = 0, kb = 0) of the whole tiled W (§3.4); 4-byte aligned |
| 2 | `0x8008` | C_BASE | r/w | byte EVA of C, row-major T × NC halfwords; 4-byte aligned |
| 3 | `0x800C` | T | r/w | rows, 1..T_MAX = 128 |
| 4 | `0x8010` | K | r/w | multiple of NA, NA..K_MAX = 3072 |
| 5 | `0x8014` | NC | r/w | C's row stride in elements; multiple of NA |
| 6 | `0x8018` | CB_START | r/w | first column block (also selects W tiles: `:280`) |
| 7 | `0x801C` | CB_COUNT | r/w | column blocks in this launch; ≥ 1 (the driver never launches 0, `main.c:40`) |
| 8 | `0x8020` | SHIFT | r/w | signed; SF16 pop right-shift (§4.1); ignored for FP16 and BF16 |
| 9 | `0x8024` | DONE_ADDR | r/w | word EPA of the flag in the launching core's DMEM |
| 10 | `0x8028` | START | write | any value; starts the launch (`:163,497`) |
| 11 | `0x802C` | STATUS | read | bit 0: busy |
| 12 | `0x8030` | CYCLE | read | free-running cycle counter |
| 13 | `0x8034` | BUSY_CYC | read | busy cycles |
| 14 | `0x8038` | LOADS | read | 32-bit remote loads issued |
| 15 | `0x803C` | STORES | read | 32-bit result stores issued |
| 16 | `0x8040` | FORMAT | read | 0 SF16, 1 FP16, 2 BF16 (`:99`) |
| 17 | `0x8044` | PASSES | read | passes run |
| 18 | `0x8048` | WAIT_W | read | cycles a ready pass waited for its weight tile |
| 19 | `0x804C` | NA | read | array size; the W layout must match it |
| 20 | `0x8050` | {P, L} | read | `[31:16]` product stages (MUL_ST), `[15:0]` partial-sum stages per PE |

(Map at `:33-38`, read mux at `:167-181`.)

- **CSR writes are dropped while busy** (`:190`). START while busy is ignored, with a simulation `$error` (`:618`).
- **Out-of-range T, K or NC** produce a simulation `$error` only (`:619-620`). The hardware does not check them.
- **The descriptor registers persist** across launches (reset only with the pod, `:184-186`), so a runtime need rewrite only the fields that change.
- **Counters 12-18 are cumulative** (`:485,492-493`).

### 3.3 Build-time parameters per tile module

`sf_hb_v3.sv:59-62,95-112,675-702`:

| Module | FMT | Input | Accumulator | Product truncation | L | P = MUL_ST | NA |
|---|---|---|---|---|---|---|---|
| `sf_hb_v3_sf16[_m2]` | 0 | SF16 | SF24, Q5.19 (FRAC 19, ACC_W 24) | TRUNC_K 9, COMP 1024 | 1 | 1 [2] | 8 |
| `sf_hb_v3_fp16[_m2]` | 1 | FP16 (5/10) | FP24 (1/8/15) | TRUNC_K 4, COMP 12 | 3 (ALIGN_STAGE 1) | 1 [2] | 8 |
| `sf_hb_v3_bf16[_m2]` | 1 | BF16 (8/7) | FP24 (1/8/15) | none (exact) | 3 | 1 [2] | 8 |
| `*_a4` / `*_m2a4` | as above | | | | | 1 / 2 | 4 |

- **All modules:** CT = 1 (carry-save multiplier), CG = 1, `T_MAX` 128, `K_MAX` 3072, `WS` 4 weight slots, 32 tags, 32 outstanding credits.
- **MUL_ST, CT and NA do not change the numerics.**
  - MUL_ST = 2 gives "the same product, one cycle later" (`hb/v3/v3_pe.sv:33-36`).
  - CT is the same sum written as a carry-save tree.
  - The k order is the same for any NA.
- **NA changes only the W layout and the column-block width.** That is why `run_v3.sh:13` uses a separate launch set (`$V3L_a4`) for 4 × 4 tiles.

### 3.4 Data layouts in DRAM

All operands are 16-bit values, packed two per 32-bit word, little-endian: the even index is in the low half (`:547-548,551-552,606`). gen_v3 emits plain `unsigned short` arrays in `.dram`, 64-byte aligned (`hb/sw/v3/gen_v3.py:21-24`).

- **A: row-major T × K.**
  - The tile loads it in full, once per launch, with `LW` from `A_BASE + 4i` for i < T·K/2 (`:202,259,279`).
  - It scatters A[t][k] into bank `k mod NA` at address `t·K/NA + k/NA` (`:206,520-528,546-548`).
- **W: NA × NA tiles.**
  - Tile (cb, kb) is at tile index `cb·(K/NA) + kb`. Each tile is NA² halfwords, row-major: row r = k − NA·kb, column c = n − NA·cb.
  - Byte address of W[k][n]: `W_BASE + 2·((cb·K/NA + kb)·NA² + r·NA + c)`.
  - The RTL (`:280,551-552`) and `prepare_v3.tiles()` (`hb/sw/v3/prepare_v3.py:75-79`) agree; I checked both for NA = 8 and 4. In numpy:

    ```python
    W.reshape(K//NA, NA, N//NA, NA).transpose(2, 0, 1, 3).reshape(-1)
    ```

  - CB_START indexes the whole tiled matrix, so W_BASE is always the base of all of W, never of a slice.
- **C: row-major T × NC.**
  - The tile writes word EVA `C_BASE + 2·(t·NC + c)`, with c even and mask `1111` (`:604-606,313`).
  - Tiles with disjoint column blocks never share a word.
  - C may be a sub-matrix of a wider buffer: NC is just the stride.
- **SF16 scales are not on the tile.** The per-tensor exponents of A, W and C live only in the compiler. The tile sees integers and SHIFT (§4.1).

What `prepare_v3.py` produces per launch: `<out>/<fmt>/<name>.npz` with `A` (row-major words), `W` (already tiled for `NA` from the environment), `C` (expected, row-major), and `T`, `K`, `N`, `shift`, `name` (`:115-116`). gen_v3 turns that into `launch.h`: `T K N SHIFT` defines and the arrays `A`, `Wt`, `Cexp` (`gen_v3.py:20-24`).

### 3.5 Internal limits and ordering (what a scheduler can rely on)

- **Request priority each cycle: result store, then A load, then W load** (`:266-273`).
  - All A requests are issued before any W request (`:260`).
  - No pass starts until all of A has arrived (`:349,362`). So within one launch, loading A never overlaps compute.
- **Outstanding requests.** Loads carry a 5-bit tag in `reg_id` (32 tags, `:107,215-229,320`). Loads and stores together are capped at 32 outstanding credits (`:258`).
- **Weight slots.** W tiles stream in (cb, kb) order into 4 slots, slot = tile index mod 4, up to 4 tiles ahead of the array (`:260,531`). A slot frees once its tile is shifted in (`:556-561`).
  - No W tile is reused or cached across column blocks or launches.
- **Store FIFOs.** There are NA/2 FIFOs, each `T_MAX` deep, with a ring of 8 passes in flight (`:108,240-243`). The last pass of a column block waits for room for T results in each FIFO (`:355-363`).
- **C is complete only at DONE.** Stores leave in no fixed order.
- **Do not modify A or W until DONE.** W is read throughout the launch.
- **Do not alias C with A or W across tiles.** Four tiles share A, and one may still be loading it while another stores.
- **Done condition:** all passes retired, store FIFOs empty, no credits outstanding, no tags busy; then the DONE store (`:507-509`).

### 3.6 What a runtime does to run one GEMM

1. **At initialisation, check the machine.** Read CSR 19 (NA) and CSR 16 (FORMAT) of each tile and assert they match what the weights were laid out and quantised for (`hb/sw/v3/main.c:35`).
2. **Get the operands into DRAM.**
   - A: row-major (T × K, halfwords in the tile's format).
   - W: pre-tiled for NA.
   - C: an allocated buffer.
   - Everything 4-byte aligned; 64-byte alignment, as gen_v3 does, also aligns to vcache lines.
   - If this core stored any of them itself, call `bsg_fence()`.
3. **Split the column blocks.** The driver splits `cbs = N/NA` blocks into four contiguous ranges `[cbs·t/4, cbs·(t+1)/4)` and skips empty ranges (`main.c:37-40`).
4. **For each tile with work** (`main.c:41-52`):
   1. Make sure it is idle: its previous flag is set, or STATUS bit 0 is 0.
   2. Write CSRs 0-9.
   3. Set `flag[t] = 0`.
   4. Write CSR 10.
5. **Wait:** spin while `!flag[t]` for each launched tile (`main.c:55-56`).
6. **Use C.** It is complete and visible through the vcaches. It can be the next GEMM's A directly: row-major in and row-major out, and for SF16 the next `e_A` is this `e_C`.

A runtime sketch, derived from `hb/sw/v3/main.c`:

```c
enum { A_BASE, W_BASE, C_BASE, T_, K_, NC_, CB_START, CB_COUNT, SHIFT_, DONE_ADDR, START,
       STATUS, CYCLE, BUSY_CYC, LOADS, STORES, FORMAT, PASSES, WAIT_W, NA_, PL };
static volatile int sf_flag[4];                         /* in DMEM: the default section, not .dram */
static inline void sf_wr(int x, int i, int v) { bsg_global_pod_store(0, 0, x, 1, (0x2000 + i) << 2, v); }
static inline int  sf_rd(int x, int i) { int v; bsg_global_pod_load(0, 0, x, 1, (0x2000 + i) << 2, v); return v; }

void sf_v3_launch(int x, const void *a, const void *w, void *c, int t, int k, int nc,
                  int cb0, int ncb, int shift) {
  sf_wr(x, A_BASE, (int) a);  sf_wr(x, W_BASE, (int) w);  sf_wr(x, C_BASE, (int) c);
  sf_wr(x, T_, t);  sf_wr(x, K_, k);  sf_wr(x, NC_, nc);
  sf_wr(x, CB_START, cb0);  sf_wr(x, CB_COUNT, ncb);  sf_wr(x, SHIFT_, shift);
  sf_wr(x, DONE_ADDR, ((int) &sf_flag[x]) >> 2);
  sf_flag[x] = 0;
  sf_wr(x, START, 1);
}
static inline void sf_v3_wait(int x) { while (!sf_flag[x]) ; }
```

**Two ways to split work across tiles** (both follow from the address arithmetic):

- **N split** (the driver's). Every tile loads all of A, and W is split, so A traffic is 4×. This is right when T·K is small next to K·N, as for the LM head with T = 1.
- **T split** (not exercised). Tile i takes rows [t0, t1):
  - `A_BASE += 2·t0·K`, `C_BASE += 2·t0·NC`, T = t1 − t0;
  - all column blocks;
  - every tile loads all of W.

  This is right when T·K is large next to K·N. Both offsets stay 4-byte aligned, because K and NC are multiples of NA.

**Cost model, from the RTL.** The counts per launch match the records exactly, e.g. `scores_t32` (loads 5,120) and `lmhead_c2048` (loads 787,968, passes 24,576 or 98,304) in `hb/results/v3*_*.jsonl`:

- loads = Σ over launched tiles of T·K/2, plus K·N/2;
- stores = T·N/2;
- passes = (N/NA)·(K/NA).

On time:

- A pass occupies the array for at least max(T, NA·L + 3) cycles (`:111,572-573`).
- The pod's 8 vcaches deliver about 1.4 words per cycle to the four tiles together, so the tiles are bandwidth-bound (`docs/hammerblade.md:147`).

---

## 4. Numerics a compiler must match

**Bit-exact reference:** `hb/sw/v3/mxu_emu.py` (a copy of study S1's emulator), as `prepare_v3.py:49-72` calls it. I checked both pops below against a transliteration of the RTL pop functions: 0 mismatches in 200k SF16 cases and in 100k FP16 and 100k BF16 cases.

### 4.1 SF16 (v3)

**In memory: sign-magnitude, not two's complement.**

- Word = `s<<15 | m`, m ≤ 32767 (`prepare_v3.py:39-40`).
- Value = (−1)^s · m · 2^(e − 15), where e is a per-tensor exponent chosen so that max|x| / 2^e < 1: `scale_exp(m) = floor(log2 m) + 1`, either sign allowed (`mxu_emu.py:59-63`).
- Quantisation: `m = min(rint(|x|·2^(15−e)), 32767)`, round half to even (`:66-70`).
- Write zero as `0x0000`. The processing element tolerates `0x8000` (zero magnitude gives a zero product), and the pop never emits it (`sf_hb_v3.sv:427`).

**Product:**

1. The 15 × 15 magnitude product (Q0.30) has its partial-product bits in columns < 9 dropped, and COMP = 1024 is added.
2. It is truncated (>> 11) to 19 fraction bits.
3. It is signed by s_a ⊕ s_w.

(`hb/v3/v3_pe.sv:21-31,66-100`; `mxu_emu.k_fix_t` with `drop = 11, width = 24, tk = 9, comp = 1024`, `:106-148`.) The dropped set is symmetric in a and w, so the product is commutative.

**Accumulator: SF24 (Q5.19), 24-bit two's complement, saturating at every add** to [−2^23, 2^23 − 1] (`v3_pe.sv:163-167`). Additions run in strict k order, so saturation makes the result order-dependent. Do not reorder K or split it.

**Pop:**

- mag = |acc|.
- If SHIFT > 0: q = round-half-even(mag / 2^SHIFT), on the magnitude, so rounding is symmetric. If SHIFT ≥ 63, q = 0.
- If SHIFT ≤ 0: q = mag << −SHIFT, with no rounding.
- q = min(q, 32767); out = q ? `s<<15 | q` : `0x0000`.

(`sf_hb_v3.sv:410-428`.) Emulating this with an arithmetic shift on two's complement gives wrong ties for negative values.

**SHIFT from the exponents:** `SHIFT = 19 − 15 + e_C − (e_A + e_W) = 4 + e_C − e_A − e_W` (`prepare_v3.py:59`). The output word then has exponent e_C.

- `prepare_v3` picks e_C from the actual result's max, an oracle (`:57-58`, `mxu_emu.pop_sf16:151-163`).
- A compiler must pick e_C statically (calibration) and test against references computed with its own SHIFT through the pop above, not against prepare_v3's.

### 4.2 FP16 and BF16 (v3)

**In memory:**

- FP16: IEEE binary16.
- BF16: the top 16 bits of an FP32 (`prepare_v3.py:43-46`).
- Operands are quantised by the host from float64: round to nearest even, values below the smallest normal become signed zero, overflow becomes ±inf (`mxu_emu.fp_round`, `:176-190`; FMTS at `:168-173`).
- The tile reads any subnormal input as signed zero (`hb/v3/fp_arith_v3.sv:18-19`). Flush subnormals before comparing with a reference.

**Per MAC:** psum = round_FP24(a·w + psum), one RNE rounding into FP24, with:

- FP24: 1 sign, 8 exponent bits (bias 127), 15 mantissa bits;
- results tiny before rounding (< 2^−126) flushed to signed zero;
- overflow to ±inf;
- any NaN becoming canonical NaN;
- IEEE zero signs (`fp_arith_v3.sv:15-23`, `v3_pe.sv:177-185`).

**Product:**

- FP16: the 11 × 11 significand product with partial-product columns < 4 dropped, and COMP = 12 added (`mxu_emu.k_fpnat_t` with `tk = 4, comp = 12`, `:227-277`).
- BF16: exact (`mxu_emu.k_fpnat`, `:193-224`).

**Pop, FP24 to 16 bits** (`sf_hb_v3.sv:432-454`):

- round to nearest even;
- any value below the format's smallest normal, before rounding, becomes signed zero;
- overflow becomes ±inf (no saturation);
- NaN becomes `0x7E00` (FP16) or `0x7FC0` (BF16).

This equals `fp_round(acc, fmt)` (`prepare_v3.py:72`).

### 4.3 v1 numerics (for completeness)

- **SF16:** each PE step adds `(|a|·|w|) >> 15` (Q1.15, truncated, sign applied) into a 16-bit two's-complement sum that saturates to ±32767. Rows are combined with the ACT add, and the output is sign-magnitude (`test/gpt2/kernels.py:195-238`).
- **FP16 and BF16:** one fused rounding to the 16-bit format per MAC (`test/gpt2/formats.py`).
- The v1 hardware has no shift: values live in [−1, 1).

### 4.4 Zero padding

Padding K or N with zeros to a multiple of NA is exact in all three formats. The one exception is a FP accumulator at −0, which adding a +0 product turns into +0.

**A possible ±0 divergence (not verified):**

- The emulator skips a = 0 terms (`mxu_emu.py:209,245`), while the hardware adds the signed-zero product.
- After an FP24 underflow to −0, the hardware can give +0 where the emulator keeps −0.
- None of the 180 launches showed this.

---

## 5. Toolchain, build and test

**Run all of this on Linux** with Verilator 5 and upstream's RISC-V GCC (the research server or a RunPod pod, not the Mac). From `hb/README.md:52-63`:

```bash
# once: upstream sources, simulator deps, and RISC-V GCC
git clone https://github.com/bespoke-silicon-group/bsg_manycore.git
git clone https://github.com/bespoke-silicon-group/basejump_stl.git
make -C bsg_manycore checkout_submodules && make -C basejump_stl/imports DRAMSim3
make -C bsg_manycore/software/riscv-tools checkout-riscv-gnu-tools build-riscv-gnu-tools
hb/setup_pod.sh bsg_manycore .        # patches + copies hb/machines/* into bsg_manycore/machines
# one machine (the Verilator model), per machine name from section 1
make -C bsg_manycore/machines sf_4x2_sf16/simsc BSG_PLATFORM=verilator IGNORE_CADENV=1
make -C bsg_manycore/machines v3_4x2_sf16/simsc BSG_PLATFORM=verilator IGNORE_CADENV=1
```

The third `make` line comes from the README's "`software/riscv-tools`: `checkout-riscv-gnu-tools build-riscv-gnu-tools`". The README gives only the `sf_4x2` build line; the `v3` line follows the same pattern for the machines `setup_pod.sh:45-48` copies.

**`setup_pod.sh` patches four things upstream** (`hb/README.md:39-48`):

1. The file list (`hb/sf_filelist.mk`). It also generates `hb/build/sf_v1_prefixed.sv`, with the v1 modules renamed `sf1_*` by `hb/v1_prefix.py`.
2. The row-type define.
3. The pass-through of `SF_MACHINE_DEFINES`.
4. `test.cpp`, which must wait for reset to rise.

**v3 test vectors** need GPT-2 small: `GPT2_DIR` with `model.safetensors` and `tokenizer.json`, plus numba.

```bash
NA=8 python3 hb/sw/v3/prepare_v3.py $V3L 8 32 128          # -> $V3L/<fmt>/<name>.npz
NA=4 python3 hb/sw/v3/prepare_v3.py ${V3L}_a4 8 32 128     # W tiled for the a4 machines
```

**Run one v3 GEMM** (`hb/run_v3.sh:3-20`):

```bash
MC=$PWD/bsg_manycore ROOT=$PWD RUNS=$PWD/runs V3L=$V3L hb/run_v3.sh sf16 fc1_t32               # machine v3_4x2_sf16
MC=... ROOT=... RUNS=... V3L=$V3L MACH=v3i hb/run_v3.sh fp16_m2a4 lmhead_c2048                 # machine v3i_4x2_fp16_m2a4, uses ${V3L}_a4
```

The script does three things:

1. `gen_v3.py <npz> launch.h`.
2. Copies `hb/sw/v3/{main.c,Makefile}` into `$RUNS/<MACH>_<fmt>/<name>/`.
3. Runs `make main.run BSG_MANYCORE_DIR=$MC SF_FMT=<fmt> MACH=<MACH>`. This builds `main.riscv` through upstream's `Makefile.master` and `Makefile.tail_rules` and runs it on `machines/<MACH>_4x2_<fmt>`, with `MAX_CYCLES` 400 M (`hb/sw/v3/Makefile:8-11`).

**Run one v1 launch:** `hb/run_launch.sh <fmt>[_rb] <name>` (`gen_launch.py` → `hb/sw/main.c`). Batches go through `hb/run_all.sh <names> <fmt>...` (`hb/README.md:60-61`).

**Bit-exactness and where results land:**

- **The check.** The driver compares every C word with `Cexp` (v1: `win[exp_addr[i]]` with `exp_word[i]`). It prints one `SFHB ... mismatches=N` line and calls `bsg_fail()` on any mismatch (`hb/sw/v3/main.c:59-63,75-78`, `hb/sw/main.c:79-97`).
- **The record.** `hb/parse_run.py` turns `run.log` into one JSON record appended to `$RUNS/<MACH>_<fmt>.jsonl` (v1: `$RUNS/<fmt>.jsonl`).
  - `finish` = `BSG_FINISH` seen and no `BSG_FAIL`.
  - `errors` counts `BSG_ERROR`, `[sf_hb_accel]`, `%Error` and `Assertion failed`. `[sf_hb_v3]` is not matched by name; it is caught only if Verilator prints `$error` with `%Error` (`:17-19`).
  - The `pl` field is printed with `%x`, so `10003` means P = 1, L = 3.
- **The run directory** `$RUNS/<MACH>_<fmt>/<name>/run.log` keeps the log.
- **Committed copies** live in `hb/results/`.

---

## 6. Suggested compiler and runtime split

| Layer | Produces | Notes |
|---|---|---|
| **Clang/LLVM (stock RISC-V backend)** | Host code for the vanilla cores: runtime, driver loop, host operations (LayerNorm, softmax, GELU, re-tiling, quantisation) | `riscv32`, RV32IMAF. Match upstream's `-march`, `-mabi`, code model, `crt.o`, linker script and `libbsg_manycore_runtime` ABI [upstream `software/mk/Makefile.builddefs`, `Makefile.master`]. Needs `__attribute__((section(".dram")))` for large arrays, and compatible handling of upstream's inline asm in `bsg_manycore.h`. No SuperFloat backend is needed: v3 has no ISA. |
| **Runtime library (C, on vanilla cores)** | `sf_v3_launch/wait/poll` (§3.6); machine probe (CSR 16, 19, 20); the N-split and T-split helpers; DMEM flag management; counter snapshots; for v1, program upload and the block dispatcher | MMIO goes through `volatile` 32-bit stores and loads via `bsg_global_pod_{store,load}`. Spin on DMEM flags. `bsg_fence()` after writing operands. Several vanilla cores can each own tiles. |
| **Graph compiler** | Per GEMM: a descriptor `{A, W, C, T, K, NC, CB_START, CB_COUNT, SHIFT}` per tile, the tile assignment, and the DRAM layouts | Pre-tiles weights for the machine's NA, offline. Chooses SF16 exponents per tensor and computes SHIFT. Tiles GEMMs to T ≤ 128 and K ≤ 3072, with K and N padded to multiples of NA. Schedules runtime re-tiling for operands produced at runtime that are used as W. Lays out C where the next op wants it. |

**Pitfalls:**

1. **SF16 in DRAM is sign-magnitude.** Rounding at the pop is round-half-even on the magnitude. Never emit `0x8000`.
2. **The SF16 output exponent is a compile-time decision.** The test vectors use an oracle e_C. Accumulators saturate per add in k order.
3. **No split-K and no accumulate.** A launch always starts from zero and rounds once at the end. K > 3072 means partial outputs plus a host add: an extra rounding, and different numerics from one launch.
4. **W must be pre-tiled** (NA × NA, column block major, then k block). The tile writes C row-major only. So a GEMM output used as the next W must be re-tiled on the vanilla cores; A operands chain directly.
   - Attention's K^T (scores) and V (av) are such operands (`prepare_v3.py:87-95`).
5. **The layout depends on NA (8 or 4).** Check CSR 19 against the build.
   - The column-block width is NA, not 8 (the comment at `sf_hb_v3.sv:14` is stale).
   - CB_START indexes the whole tiled W.
6. **Alignment and shape rules:**
   - all bases 4-byte aligned;
   - K and NC multiples of NA; T in 1..128;
   - CB_COUNT ≥ 1;
   - CB_START + CB_COUNT ≤ NC/NA, assuming W has NC columns.

   The hardware does not check these.
7. **CSR writes while busy are silently dropped (v3).** On v1 they are not gated and corrupt a running block. Wait for DONE before reprogramming.
8. **Clear the done flag before START.** The flag must be in the launching core's DMEM, and DONE_ADDR is a word EPA, not an EVA.
9. **Counters are cumulative.** Use differences.
10. **Every N-split tile reloads all of A**, and A loading never overlaps compute within a launch. Choose N-split or T-split per GEMM (§3.6).
11. **FP formats overflow to inf and flush subnormals** in inputs, accumulator and pop. There is no saturating mode.
12. **v1 reaches only halfwords 0..0xFFBF from BASE**, and BASE must be even. Its read buffer is not coherent within a block. It is not a sensible compiler target.

---

## 7. What to look up upstream

- **`bsg_manycore.h`:** the EVA encoding behind `bsg_global_pod_store`/`load`; `bsg_fence`, `bsg_lw_prefetch`, `bsg_set_tile_x_y`, `bsg_printf`, `bsg_finish`, `bsg_fail`.
- **Vanilla core:** the EVA map (DRAM `0x8000_0000`+, local DMEM, tile-group and global EVAs) and why `&dmem_var >> 2` is that tile's EPA.
- **`bsg_manycore_eva_to_npa`:** including IPOLY hashing.
- **Packets and endpoint:** the packet struct (`op_v2`, `reg_id`, `store_mask_s`, `load_info_s` in `bsg_manycore_pkg`), and `bsg_manycore_endpoint_standard` credit semantics.
- **Build:** `software/mk/Makefile.master`, `Makefile.builddefs`, `Makefile.tail_rules` (flags, `-march`/`-mabi`, linker script, `.dram` placement, the loader that preloads `.dram` into the DRAM model, `VCACHE_*` defines).
- **Network and core behaviour:** in-order delivery per source/destination pair; vanilla-core interrupt support; vcache flush for an external host.

## 8. What I could not determine from our code

- The exact EVA bit layout of `bsg_global_pod_*`, the DMEM EPA mapping, and what pod (0,0) means in those macros.
- Whether the network guarantees that the CSR stores reach the tile before START. The drivers assume it, without a fence, and 708 launches passed.
- Upstream's vanilla-core compile flags (ABI, code model), and whether upstream supports or ships Clang/LLVM.
- Whether the vanilla core can take interrupts. Our tiles use polling only.
- How a compiler should choose the SF16 output exponent and SHIFT ahead of time. Our vectors use the data's own max.
- Whether the emulator's skip of zero operands can differ from the hardware in the sign of a zero FP result (§4.4). This is reasoned, not run.
- Physical realism of the sizes. `T_MAX × K_MAX` implies a 768 KiB activation buffer per tile, a simulation size. A hardened tile would likely shrink these limits, and the compiler constraints with them.
- The full v1 ISA semantics beyond the encoding table (see `src/decoder.sv` and `src/core.sv`).
