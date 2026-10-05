#!/bin/bash
# S1 full run: the v2 16-bit SF16 accumulator on 4 windows (it fails by a
# wide margin), every other case on 32.
cd "$(dirname "$0")"
export KMP_DUPLICATE_LIB_OK=TRUE
CASES=sf16_sat16,sf16_sat16h python3 s1_numerics.py 4 results/s1_sat16.json 2>&1 | grep -v OMP
CASES=sf16_sf24,sf16_sf32,fp16_nat,fp16_fp24,fp16_fp32,bf16_nat,bf16_fp24,bf16_fp32 \
    python3 s1_numerics.py 32 results/s1_main.json 2>&1 | grep -v OMP
echo S1_DONE
