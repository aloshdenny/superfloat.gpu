// HammerBlade driver for one GEMM C = A W on the four v3 matrix tiles of row
// 1 (hb/v/sf_hb_v3.sv). Runs on the vanilla core at (0,0):
//   1. evicts the vcaches (as sw/main.c), so operands come from DRAM;
//   2. splits the N/NA column blocks into four contiguous ranges, writes each
//      tile's launch registers and starts it; a tile stores 1 into
//      done_flag[tile] when its results are all in DRAM;
//   3. checks every result word against the bit-exact reference.
// Cycles are read from tile 0's free-running counter around step 2. C goes
// to a DRAM region outside the program, so it is not preloaded.
#include "bsg_manycore.h"
#include "bsg_set_tile_x_y.h"
#include "launch.h"

#define NACC     4
#define ACC_Y    1
#define CSR(i)   ((0x2000 + (i)) << 2)
#define C_EVA    0x88000000
#define EVICT_EVA   0x81000000
#define EVICT_BYTES (4 * VCACHE_CAPACITY_WORDS * 4)

static volatile int done_flag[NACC];

static inline void acc_store(int t, int csr, int v) { bsg_global_pod_store(0, 0, t, ACC_Y, CSR(csr), v); }
static inline int acc_load(int t, int csr) { int v; bsg_global_pod_load(0, 0, t, ACC_Y, CSR(csr), v); return v; }

int main()
{
  bsg_set_tile_x_y();
  if (__bsg_x != 0 || __bsg_y != 0) bsg_wait_while(1);

  for (int a = 0; a < EVICT_BYTES; a += VCACHE_BLOCK_SIZE_WORDS * 4)
    bsg_lw_prefetch((int *) (EVICT_EVA + a));
  bsg_fence();

  int na = acc_load(0, 19);                    // the tiles' array size (Wt was laid out for it)
  int t0 = acc_load(0, 12);
  int cbs = N / na, launched = 0;
  for (int t = 0; t < NACC; t++) {
    int s = cbs * t / NACC, e = cbs * (t + 1) / NACC;
    if (e == s) continue;
    acc_store(t, 0, (int) A);
    acc_store(t, 1, (int) Wt);
    acc_store(t, 2, C_EVA);
    acc_store(t, 3, T);
    acc_store(t, 4, K);
    acc_store(t, 5, N);
    acc_store(t, 6, s);
    acc_store(t, 7, e - s);
    acc_store(t, 8, SHIFT);
    acc_store(t, 9, ((int) &done_flag[t]) >> 2);
    done_flag[t] = 0;
    acc_store(t, 10, 1);
    launched |= 1 << t;
  }
  for (int t = 0; t < NACC; t++)
    if (launched >> t & 1) while (!done_flag[t]) ;
  int t1 = acc_load(0, 12);

  int mismatches = 0;
  volatile unsigned *c = (volatile unsigned *) C_EVA;
  unsigned *x = (unsigned *) Cexp;
  for (int i = 0; i < T * N / 2; i++)
    if (c[i] != x[i]) mismatches++;

  int loads = 0, stores = 0, passes = 0, wait_w = 0, busy_max = 0;
  for (int t = 0; t < NACC; t++) {
    if (!(launched >> t & 1)) continue;
    loads += acc_load(t, 14);
    stores += acc_load(t, 15);
    passes += acc_load(t, 17);
    wait_w += acc_load(t, 18);
    int b = acc_load(t, 13);
    if (b > busy_max) busy_max = b;
  }
  bsg_printf("SFHB name=%s fmt=%d pl=%x na=%d t=%d kc=%d n=%d cycles=%d loads=%d stores=%d passes=%d wait_w=%d busy_max=%d outputs=%d mismatches=%d\n",
             LAUNCH_NAME, acc_load(0, 16), acc_load(0, 20), na, T, K, N, t1 - t0, loads, stores, passes, wait_w, busy_max,
             T * N, mismatches);
  if (mismatches) bsg_fail();
  bsg_finish();
  bsg_wait_while(1);
}
