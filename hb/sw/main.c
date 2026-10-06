// HammerBlade driver for one GPT-2 launch on the SuperFloat v1 tiles.
//
// Runs on the vanilla core at (0,0) of the 4x2 pod; the four tiles of row 1
// are SuperFloat v1 core tiles (hb/v/sf_hb_accel.sv). It plays the role of
// the OpenFrame chip's block dispatcher:
//   1. evicts the vcaches (reads 4x their capacity elsewhere in DRAM), so
//      the launch's operands come from DRAM, as from host memory on the chip;
//   2. writes the kernel into each tile's program memory and the window base;
//   3. hands out the NB thread blocks: each free tile gets the next block, and
//      a tile reports a finished block by storing 1 into done_flag[tile];
//   4. checks every stored output against the bit-exact reference.
// Cycles are read from tile 0's free-running counter around steps 2-3.

#include "bsg_manycore.h"
#include "bsg_set_tile_x_y.h"
#include "launch.h"

#define NACC        4
#define ACC_Y       1
#define PMEM(i)     ((i) << 2)
#define CSR(i)      ((0x2000 + (i)) << 2)
#define CSR_BASE    0
#define CSR_DONE    1
#define CSR_START   2
#define CSR_CYCLE   4
#define CSR_BUSY    5
#define CSR_READS   6
#define CSR_WRITES  7
#define CSR_FORMAT  8
#define CSR_BLOCKS  9
#define CSR_LOADS   10
#define CSR_RBLINES 11

#define EVICT_EVA   0x81000000
#define EVICT_BYTES (4 * VCACHE_CAPACITY_WORDS * 4)

static volatile int done_flag[NACC];

static inline void acc_store(int t, int addr, int v) { bsg_global_pod_store(0, 0, t, ACC_Y, addr, v); }
static inline int acc_load(int t, int addr) { int v; bsg_global_pod_load(0, 0, t, ACC_Y, addr, v); return v; }

static inline void launch(int t, int block)
{
  done_flag[t] = 0;
  acc_store(t, CSR(CSR_START), block | (8 << 8));
}

int main()
{
  bsg_set_tile_x_y();
  if (__bsg_x != 0 || __bsg_y != 0) bsg_wait_while(1);

  for (int a = 0; a < EVICT_BYTES; a += VCACHE_BLOCK_SIZE_WORDS * 4)
    bsg_lw_prefetch((int *) (EVICT_EVA + a));
  bsg_fence();

  int t0 = acc_load(0, CSR(CSR_CYCLE));

  for (int t = 0; t < NACC; t++) {
    for (int i = 0; i < PROG_LEN; i++) acc_store(t, PMEM(i), prog[i]);
    acc_store(t, CSR(CSR_BASE), (int) win);
    acc_store(t, CSR(CSR_DONE), ((int) &done_flag[t]) >> 2);
  }

  int next = 0, finished = 0;
  for (int t = 0; t < NACC && next < NB; t++) launch(t, next++);
  while (finished < NB) {
    for (int t = 0; t < NACC; t++) {
      if (done_flag[t]) {
        done_flag[t] = 0;
        finished++;
        if (next < NB) launch(t, next++);
      }
    }
  }

  int t1 = acc_load(0, CSR(CSR_CYCLE));

  int mismatches = 0;
  for (int i = 0; i < N_EXP; i++)
    if (win[exp_addr[i]] != exp_word[i]) mismatches++;

  int reads = 0, loads = 0, writes = 0, blocks = 0;
  for (int t = 0; t < NACC; t++) {
    reads  += acc_load(t, CSR(CSR_READS));
    loads  += acc_load(t, CSR(CSR_LOADS));
    writes += acc_load(t, CSR(CSR_WRITES));
    blocks += acc_load(t, CSR(CSR_BLOCKS));
  }
  bsg_printf("SFHB name=%s fmt=%d rb=%d gemv=%d kc=%d nb=%d cycles=%d reads=%d loads=%d writes=%d blocks=%d outputs=%d mismatches=%d",
             LAUNCH_NAME, acc_load(0, CSR(CSR_FORMAT)), acc_load(0, CSR(CSR_RBLINES)), KERNEL_IS_GEMV, KC, NB,
             t1 - t0, reads, loads, writes, blocks, N_EXP, mismatches);
  for (int t = 0; t < NACC; t++)
    bsg_printf(" busy%d=%d", t, acc_load(t, CSR(CSR_BUSY)));
  bsg_printf("\n");

  if (mismatches) bsg_fail();
  bsg_finish();
  bsg_wait_while(1);
}
