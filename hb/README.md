# SuperFloat v1 on HammerBlade

The v1 core tile (`src/core_tile.sv`, the OpenFrame chip's compute macro) as an accelerator tile in a HammerBlade manycore pod. HammerBlade is the Bespoke Silicon Group's `bsg_manycore`: RISC-V "vanilla" cores on a 2D mesh with vcaches in front of DRAM. All three number formats (SF16, FP16, BF16) run the GPT-2 kernels on the HammerBlade RTL, with every output checked bit for bit. Results are in `docs/hammerblade.md`.

## What is new

| File | What it is |
|---|---|
| `v/sf_hb_accel.sv` | The adapter: one v1 `core_tile` behind a `bsg_manycore_endpoint_standard`, plus one module per format and adapter (`sf_hb_accel_sf16`, `_fp16`, `_bf16`, and `_rb` with the read buffer) |
| `v/bsg_manycore_hetero_socket.sv` | Upstream's socket with six more tile types: 9-11 SF16/FP16/BF16, 12-14 the same with the read buffer |
| `v1_prefix.py` | Renames every v1 module `sf1_*` in a build copy: bsg_manycore has an `alu` and an `lsu` of its own |
| `sf_filelist.mk` | The sources above, added to bsg_manycore's file list |
| `machines/sf_4x2_<fmt>[_rb]/` | A 4 x 2 pod: row 0 four vanilla cores, row 1 four SuperFloat tiles of one format |
| `setup_pod.sh` | Wires the above into a bsg_manycore checkout (four small edits, below) |
| `sw/main.c`, `sw/Makefile`, `sw/gen_launch.py` | The driver that runs one GPT-2 launch on the vanilla core at (0,0) |
| `run_launch.sh`, `run_all.sh`, `parse_run.py` | Build, run and record one launch, or a list of them |
| `sw/vanilla/`, `run_vanilla.sh` | Baseline: the same matrix multiply in FP32 on the four vanilla cores |
| `bench_hb.py`, `make_fig.py` | GPT-2 totals and the figure, from the recorded launches |
| `results/` | Every launch's record, the tile signoff numbers used, the totals |

The v1 RTL is not changed. Its modules are renamed in the build copy only.

## How the tile attaches

- **Program.** The chip's instruction cache (`src/shared_icache.sv`, 32 entries) sits in front of a local 512 x 16-bit program memory. The vanilla core writes that memory with remote stores. Any program write invalidates the cache.
- **Data.** The tile's 16-bit word address A is the halfword at byte address BASE + 2A in the manycore's DRAM space.
  - A read is a halfword remote load (LHU at the vcache).
  - A write is a remote store with a two-byte mask.
  - `core_tile` has one data channel, so one load is in flight at a time. Stores are posted, up to 32 at once.
  - With the read buffer (`RB_LINES` = 8), the adapter holds 8 vcache lines (32 bytes each, LRU). A miss fetches its line with 8 word loads in flight; a hit is answered the next cycle and prefetches the next line. Writes update a held copy. Every line is dropped at each launch.
- **Launch.** The vanilla core writes BASE and DONE_ADDR, then START with the block id and thread count. The tile then:
  1. resets its core for a cycle;
  2. runs it until `done`;
  3. waits for every store to be acknowledged;
  4. stores 1 to DONE_ADDR in the launching core's data memory.
- **Dispatch.** The vanilla core plays the chip's dispatcher: each free tile gets the next thread block.
- **CSRs.** The CSR map is at the top of `v/sf_hb_accel.sv`. It includes a cycle counter, busy cycles, and the words read and written.

## Edits to bsg_manycore (`setup_pod.sh`)

1. `machines/arch_filelist.mk` includes `hb/sf_filelist.mk`.
2. `v/bsg_manycore_tile_compute_array_ruche.sv` takes the type of each tile in row `SF_ACCEL_ROW` from `SF_ACCEL_TYPE` when both are defined.
   - Upstream's `hetero_type_vec_p` is an unpacked array parameter that Verilator 5 cannot elaborate once it is overridden, and `spmd_testbench` never sets it.
   - Machines without the defines are unchanged.
3. `machines/Makefile.verilator` passes a machine's `SF_MACHINE_DEFINES` to Verilator.
4. `testbenches/common/v/test.cpp` waits for reset to rise before arming assertions.
   - Under Verilator every register starts at 0, so `reset_o` reads 0 before reset has risen.
   - Without this, upstream's own `hello` fails on cycle 1.

## Running

On a Linux host with Verilator 5 and bsg_manycore's RISC-V GCC (`software/riscv-tools`: `checkout-riscv-gnu-tools build-riscv-gnu-tools`):

```bash
git clone https://github.com/bespoke-silicon-group/bsg_manycore.git
git clone https://github.com/bespoke-silicon-group/basejump_stl.git
make -C bsg_manycore checkout_submodules && make -C basejump_stl/imports DRAMSim3
hb/setup_pod.sh bsg_manycore .
make -C bsg_manycore/machines sf_4x2_sf16/simsc BSG_PLATFORM=verilator IGNORE_CADENV=1
MC=$PWD/bsg_manycore ROOT=$PWD RUNS=$PWD/runs hb/run_launch.sh sf16 gemv_check
MC=$PWD/bsg_manycore ROOT=$PWD RUNS=$PWD/runs JOBS=7 hb/run_all.sh names.txt sf16 fp16 bf16 sf16_rb fp16_rb bf16_rb
python3 hb/bench_hb.py && python3 hb/make_fig.py
```

The launches come from `test/gpt2/prepare.py` (`GPT2_DIR` holds GPT-2 small's `model.safetensors` and `tokenizer.json`).

Versions used: see `results/versions.txt`.
