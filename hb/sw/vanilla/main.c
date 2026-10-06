// Baseline: the same matrix multiply as one GPT-2 launch (gemv: one token,
// gemm: eight) on the four vanilla cores of row 0, in FP32, on the same 4x2
// pod as the SuperFloat tiles (which sit idle in row 1). Core c computes the
// c-th quarter of the columns, streaming W from DRAM once; for gemm its
// 8 x N/4 accumulators live in its data memory. Straightforward C at -O2,
// not tuned. Operands are the FP16 launch's values (gen_vanilla.py). Cycles
// come from SuperFloat tile 0's free-running counter, as in sw/main.c, after
// the same vcache eviction; outputs are checked against a float64 reference
// to a relative error of 1e-4.
#include "bsg_manycore.h"
#include "bsg_set_tile_x_y.h"
#include "launch.h"

#define ACC_Y       1
#define CSR_CYCLE   ((0x2000 + 4) << 2)
#define EVICT_EVA   0x81000000
#define EVICT_BYTES (4 * VCACHE_CAPACITY_WORDS * 4)
#define COLS        (N / 4)

volatile int go;
volatile int done_flag[4];
float acc[T][COLS];

int main()
{
  bsg_set_tile_x_y();
  int c = __bsg_x;
  int t0 = 0;
  if (c == 0) {
    for (int a = 0; a < EVICT_BYTES; a += VCACHE_BLOCK_SIZE_WORDS * 4)
      bsg_lw_prefetch((int *) (EVICT_EVA + a));
    bsg_fence();
    bsg_global_pod_load(0, 0, 0, ACC_Y, CSR_CYCLE, t0);
    for (int i = 1; i < 4; i++) bsg_remote_store(i, 0, &go, 1);
  } else {
    while (!go) ;
  }

  for (int t = 0; t < T; t++)
    for (int j = 0; j < COLS; j++) acc[t][j] = 0.0f;
  float *w = &W[c * COLS];
  for (int k = 0; k < K; k++) {
    float wk[COLS];
    bsg_unroll(32)
    for (int j = 0; j < COLS; j++) wk[j] = w[j];
    for (int t = 0; t < T; t++) {
      float a = x[k * T + t];
      bsg_unroll(32)
      for (int j = 0; j < COLS; j++) acc[t][j] += a * wk[j];
    }
    w += N;
  }
  for (int t = 0; t < T; t++)
    for (int j = 0; j < COLS; j++) y[t * N + c * COLS + j] = acc[t][j];
  bsg_fence();
  bsg_remote_store(0, 0, &done_flag[c], 1);

  if (c != 0) bsg_wait_while(1);
  for (int i = 0; i < 4; i++) while (!done_flag[i]) ;
  int t1;
  bsg_global_pod_load(0, 0, 0, ACC_Y, CSR_CYCLE, t1);

  int bad = 0;
  for (int j = 0; j < T * N; j++) {
    float e = y[j] - y_ref[j], m = y_ref[j] < 0 ? -y_ref[j] : y_ref[j];
    if ((e < 0 ? -e : e) > 1e-4f * (m > 1.0f ? m : 1.0f)) bad++;
  }
  bsg_printf("SFHB name=vanilla_%s fmt=-1 gemv=%d kc=%d nb=%d cycles=%d outputs=%d mismatches=%d\n",
             LAUNCH_NAME, !GEMM, K, NB, t1 - t0, T * N, bad);
  if (bad) bsg_fail();
  bsg_finish();
  bsg_wait_while(1);
}
