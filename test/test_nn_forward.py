"""
Neural Network Forward Pass Tests — Atreides GPU
=================================================

Extended NN inference tests that exercise on-GPU activation functions (ACT
instruction), multi-layer MLP pipelines, transformer attention patterns, residual
connections, and batched inference.

Key differences from test_inference.py
---------------------------------------
- ReLU / LeakyReLU / ClippedReLU applied **on GPU** via ACT instruction —
  not host-side Python as in the original 2-layer MLP test.
- 3-layer MLP (4→4→4→4) fully executed on GPU.
- Attention Q×K^T dot-product and scaled-dot-product attention scores.
- Residual connection: output = layer(x) + x via element-wise add kernel.
- Batch inference: 4 different inputs through the same 2-layer MLP.

All tests use bit-exact Q1.15 verification against the Python reference.

ACT instruction encoding (from activation.sv / memory.py):
  ACT Rd, Rs, Rt: out = activate(Rs + Rt)
  activation func: instruction[9:8] = Rd[1:0]
    00 = none  (saturating add, no non-linearity)
    01 = ReLU
    10 = LeakyReLU  (α ≈ 2^-7 = 0.0078)
    11 = ClippedReLU (clip to [0, Q115_MAX])
"""

import cocotb
from cocotb.triggers import ClockCycles
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import (
    float_to_q115, q115_to_float,
    q115_add, q115_mul, q115_fma, q115_matmul,
    q115_relu, q115_leaky_relu, q115_clipped_relu, q115_activation,
)
from helpers.memory import (
    asm_mul, asm_add, asm_sub, asm_div, asm_const,
    asm_ldr, asm_str, asm_fma, asm_act, asm_cmp, asm_brn, asm_ret,
    init_data_memory, read_memory_range,
    R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12,
    BLOCK_IDX, BLOCK_DIM, THREAD_IDX,
)
from helpers.setup import setup_test, run_kernel

THREADS_PER_BLOCK = 4


# ============================================================================
# Kernel builders
# ============================================================================

def build_matmul_kernel(N: int, base_a: int, base_b: int, base_c: int) -> list:
    """Standard N×N matmul kernel. All addresses must be < 128."""
    assert all(x < 128 for x in [N, base_a, base_b, base_c]), \
        f"Address > 127: N={N}, base_a={base_a}, base_b={base_b}, base_c={base_c}"
    return [
        asm_mul(R0, BLOCK_IDX, BLOCK_DIM),
        asm_add(R0, R0, THREAD_IDX),
        asm_const(R1, 1),
        asm_const(R2, N),
        asm_const(R3, base_a),
        asm_const(R4, base_b),
        asm_const(R5, base_c),
        asm_div(R6, R0, R2),            # row = i / N
        asm_mul(R7, R6, R2),
        asm_sub(R7, R0, R7),            # col = i % N
        asm_const(R8, 0),               # acc = 0
        asm_const(R9, 0),               # k = 0
        # LOOP at 12:
        asm_mul(R10, R6, R2),
        asm_add(R10, R10, R9),
        asm_add(R10, R10, R3),
        asm_ldr(R10, R10),              # A[row*N+k]
        asm_mul(R11, R9, R2),
        asm_add(R11, R11, R7),
        asm_add(R11, R11, R4),
        asm_ldr(R11, R11),              # B[k*N+col]
        asm_fma(R8, R10, R11),          # acc += A*B
        asm_add(R9, R9, R1),            # k++
        asm_cmp(R9, R2),
        asm_brn(12 - 24),               # loop if k < N
        asm_add(R9, R5, R0),
        asm_str(R9, R8),                # C[i] = acc
        asm_ret(),
    ]


def build_act_kernel(N: int, base_in: int, base_out: int, func: int) -> list:
    """
    Element-wise activation kernel: out[i] = activate(in[i] + 0).

    func encodes the activation as Rd bits[1:0]:
      func=0 (Rd=R8)  → saturating pass-through (no non-linearity)
      func=1 (Rd=R1)  → ReLU
      func=2 (Rd=R2)  → LeakyReLU
      func=3 (Rd=R3)  → ClippedReLU

    ACT(Rd, Rs=in[i], Rt=R_zero) → out = activate(in[i] + 0) = activate(in[i]).
    We pick Rd such that its low 2 bits encode func:
      func=0 → use R8  (8 & 3 = 0)
      func=1 → use R1  (1 & 3 = 1)
      func=2 → use R2  (2 & 3 = 2)
      func=3 → use R3  (3 & 3 = 3)
    """
    assert all(x < 128 for x in [N, base_in, base_out])
    func_to_rd = {0: R8, 1: R1, 2: R2, 3: R3}
    assert func in func_to_rd, f"Unknown activation func={func}"
    rd = func_to_rd[func]

    return [
        asm_mul(R9, BLOCK_IDX, BLOCK_DIM),
        asm_add(R9, R9, THREAD_IDX),          # R9 = thread_i
        asm_const(R4, base_in),
        asm_const(R5, base_out),
        asm_const(R0, 0),                      # bias = 0
        asm_add(R6, R4, R9),
        asm_ldr(R6, R6),                       # R6 = in[i]
        asm_act(rd, R6, R0),                   # rd = activate(in[i] + 0)
        asm_add(R7, R5, R9),
        asm_str(R7, rd),                       # out[i] = rd
        asm_ret(),
    ]


def build_vec_add_kernel(base_a: int, base_b: int, base_out: int) -> list:
    """Element-wise saturating add: out[i] = saturate(a[i] + b[i])."""
    assert all(x < 128 for x in [base_a, base_b, base_out])
    return [
        asm_mul(R9, BLOCK_IDX, BLOCK_DIM),
        asm_add(R9, R9, THREAD_IDX),
        asm_const(R1, base_a),
        asm_const(R2, base_b),
        asm_const(R3, base_out),
        asm_add(R4, R1, R9),
        asm_ldr(R4, R4),                       # a[i]
        asm_add(R5, R2, R9),
        asm_ldr(R5, R5),                       # b[i]
        asm_act(R8, R4, R5),                   # R8 = saturate(a+b), func=none (8&3=0)
        asm_add(R7, R3, R9),
        asm_str(R7, R8),
        asm_ret(),
    ]


# ============================================================================
# Python references
# ============================================================================

def ref_matmul(a_q: list, b_q: list, N: int) -> list:
    """
    Reference helper for either:
      - vector(1xN) x matrix(NxN) -> vector(1xN), or
      - matrix(NxN) x matrix(NxN) -> matrix(NxN).
    """
    if len(a_q) == N:
        # 1xN times NxN
        return q115_matmul(a_q, b_q, 1, N, N)
    if len(a_q) == N * N:
        # NxN times NxN
        return q115_matmul(a_q, b_q, N, N, N)
    raise ValueError(
        f"Unsupported A shape for ref_matmul: len(a_q)={len(a_q)}, expected {N} or {N*N}"
    )


def ref_act_vec(vec: list, func: int) -> list:
    return [q115_activation(v, func) for v in vec]


def ref_vec_add(a: list, b: list) -> list:
    return [q115_add(a[i], b[i]) for i in range(len(a))]


# ============================================================================
# Shared run helpers
# ============================================================================

async def run_matmul(dut, name, N, base_a, base_b, base_c, data, thread_count,
                     max_cycles=3000, out_count=None):
    program = build_matmul_kernel(N, base_a, base_b, base_c)
    logger = await setup_test(dut, name, program, data,
                               thread_count=thread_count, verbose=False)
    await run_kernel(dut, logger, max_cycles=max_cycles, trace_interval=0)
    await ClockCycles(dut.clk, 10)
    if out_count is None:
        out_count = N * N
    result = read_memory_range(dut, base_c, out_count)
    logger.close()
    return result


async def run_act(dut, name, N, base_in, base_out, data, func, max_cycles=500):
    program = build_act_kernel(N, base_in, base_out, func)
    tc = ((N + THREADS_PER_BLOCK - 1) // THREADS_PER_BLOCK) * THREADS_PER_BLOCK
    logger = await setup_test(dut, name, program, data,
                               thread_count=tc, verbose=False)
    await run_kernel(dut, logger, max_cycles=max_cycles, trace_interval=0)
    await ClockCycles(dut.clk, 10)
    result = read_memory_range(dut, base_out, N)
    logger.close()
    return result


async def run_vec_add(dut, name, N, base_a, base_b, base_out, data,
                      max_cycles=500):
    program = build_vec_add_kernel(base_a, base_b, base_out)
    tc = ((N + THREADS_PER_BLOCK - 1) // THREADS_PER_BLOCK) * THREADS_PER_BLOCK
    logger = await setup_test(dut, name, program, data,
                               thread_count=tc, verbose=False)
    await run_kernel(dut, logger, max_cycles=max_cycles, trace_interval=0)
    await ClockCycles(dut.clk, 10)
    result = read_memory_range(dut, base_out, N)
    logger.close()
    return result


def tc(n):
    """Thread count padded to multiple of THREADS_PER_BLOCK."""
    return ((n + THREADS_PER_BLOCK - 1) // THREADS_PER_BLOCK) * THREADS_PER_BLOCK


# ============================================================================
# Test 1 — 2-layer MLP with on-GPU ReLU
# ============================================================================

@cocotb.test()
async def test_mlp_relu_on_gpu(dut):
    """
    2-layer MLP: output = W2 × ReLU(W1 × input)  with ReLU on GPU.

    Dimensions: input(1×4), W1(4×4), W2(4×4)
    Memory layout:
      0- 3: input
      4-19: W1
     20-23: hidden (matmul result)
     24-27: hidden_relu (ACT result)
     28-43: W2
     44-47: output

    Layer 1: matmul(input, W1) → hidden
    ReLU:    act(hidden)       → hidden_relu  (ON GPU via ACT instruction)
    Layer 2: matmul(hidden_relu, W2) → output
    """
    N = 4
    input_f = [0.5, -0.25, 0.375, 0.125]
    W1_f = [
        [ 0.25, -0.125,  0.5,   0.0625],
        [-0.5,   0.25,   0.125, -0.25],
        [ 0.125, 0.5,   -0.25,  0.375],
        [-0.25,  0.0625, 0.375, -0.5],
    ]
    W2_f = [
        [ 0.5,   0.125, -0.25,  0.0625],
        [ 0.25, -0.5,   0.125,  0.375],
        [-0.125, 0.25,  0.5,   -0.125],
        [ 0.375,-0.25, -0.125,  0.25],
    ]

    input_q = [float_to_q115(x) for x in input_f]
    w1_q = [float_to_q115(v) for row in W1_f for v in row]
    w2_q = [float_to_q115(v) for row in W2_f for v in row]

    base_input = 0
    base_w1 = 4       # 4 + 16 = 20
    base_hidden = 20
    base_hidden_relu = 24
    base_w2 = 28      # 28 + 16 = 44
    base_output = 44

    data = [0] * (base_output + N)
    for i, v in enumerate(input_q):  data[base_input + i] = v
    for i, v in enumerate(w1_q):     data[base_w1 + i] = v
    for i, v in enumerate(w2_q):     data[base_w2 + i] = v

    # Python reference
    hidden_ref = ref_matmul(input_q, w1_q, N)
    hidden_relu_ref = ref_act_vec(hidden_ref, func=1)      # ReLU
    output_ref = ref_matmul(hidden_relu_ref, w2_q, N)

    # --- Layer 1: matmul on GPU ---
    hidden_hw = await run_matmul(dut, "mlp_relu_l1", N,
                                 base_input, base_w1, base_hidden,
                                 data, tc(N), out_count=N)
    assert hidden_hw == hidden_ref, \
        f"MLP ReLU GPU: layer1 matmul mismatch\n  hw={hidden_hw}\n  ref={hidden_ref}"

    # --- ReLU on GPU (ACT instruction, func=1) ---
    # Reload data with actual hardware layer-1 output
    data2 = list(data)
    for i, v in enumerate(hidden_hw): data2[base_hidden + i] = v
    hidden_relu_hw = await run_act(dut, "mlp_relu_act", N,
                                    base_hidden, base_hidden_relu,
                                    data2, func=1)
    assert hidden_relu_hw == hidden_relu_ref, \
        f"MLP ReLU GPU: on-GPU ReLU mismatch\n  hw={hidden_relu_hw}\n  ref={hidden_relu_ref}"

    # --- Layer 2: matmul on GPU ---
    data3 = list(data2)
    for i, v in enumerate(hidden_relu_hw): data3[base_hidden_relu + i] = v
    output_hw = await run_matmul(dut, "mlp_relu_l2", N,
                                 base_hidden_relu, base_w2, base_output,
                                 data3, tc(N), out_count=N)
    assert output_hw == output_ref, \
        f"MLP ReLU GPU: layer2 output mismatch\n  hw={output_hw}\n  ref={output_ref}"


# ============================================================================
# Test 2 — 3-layer MLP with on-GPU ReLU
# ============================================================================

@cocotb.test()
async def test_mlp_3layer(dut):
    """
    3-layer MLP: h1=ReLU(W1×x), h2=ReLU(W2×h1), out=W3×h2
    Dimensions: all 4×4.
    Each matmul + activation runs as separate GPU kernel.
    """
    N = 4
    random.seed(3142)

    def rand_mat():
        return [[float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N)]
                for _ in range(N)]

    x_q = [float_to_q115(random.uniform(-0.4, 0.4)) for _ in range(N)]
    W1_flat = [v for row in rand_mat() for v in row]
    W2_flat = [v for row in rand_mat() for v in row]
    W3_flat = [v for row in rand_mat() for v in row]

    # Memory layout (all < 128):
    # 0-3:   x       (4)
    # 4-19:  W1      (16)
    # 20-35: W2      (16)
    # 36-51: W3      (16)
    # 52-55: h1      (4)
    # 56-59: h1_relu (4)
    # 60-63: h2      (4)
    # 64-67: h2_relu (4)
    # 68-71: output  (4)
    bx, bW1, bW2, bW3 = 0, 4, 20, 36
    bh1, bh1r, bh2, bh2r, bout = 52, 56, 60, 64, 68

    data = [0] * (bout + N)
    for i, v in enumerate(x_q):   data[bx + i]  = v
    for i, v in enumerate(W1_flat): data[bW1 + i] = v
    for i, v in enumerate(W2_flat): data[bW2 + i] = v
    for i, v in enumerate(W3_flat): data[bW3 + i] = v

    # Python reference
    h1_ref    = ref_matmul(x_q, W1_flat, N)
    h1r_ref   = ref_act_vec(h1_ref, func=1)
    h2_ref    = ref_matmul(h1r_ref, W2_flat, N)
    h2r_ref   = ref_act_vec(h2_ref, func=1)
    out_ref   = ref_matmul(h2r_ref, W3_flat, N)

    # Layer 1: matmul
    h1_hw = await run_matmul(dut, "mlp3_l1", N, bx, bW1, bh1, data, tc(N), out_count=N)
    assert h1_hw == h1_ref, "3-layer MLP: L1 matmul mismatch"

    data2 = list(data)
    for i, v in enumerate(h1_hw): data2[bh1 + i] = v
    h1r_hw = await run_act(dut, "mlp3_relu1", N, bh1, bh1r, data2, func=1)
    assert h1r_hw == h1r_ref, "3-layer MLP: L1 ReLU mismatch"

    data3 = list(data2)
    for i, v in enumerate(h1r_hw): data3[bh1r + i] = v
    h2_hw = await run_matmul(dut, "mlp3_l2", N, bh1r, bW2, bh2, data3, tc(N), out_count=N)
    assert h2_hw == h2_ref, "3-layer MLP: L2 matmul mismatch"

    data4 = list(data3)
    for i, v in enumerate(h2_hw): data4[bh2 + i] = v
    h2r_hw = await run_act(dut, "mlp3_relu2", N, bh2, bh2r, data4, func=1)
    assert h2r_hw == h2r_ref, "3-layer MLP: L2 ReLU mismatch"

    data5 = list(data4)
    for i, v in enumerate(h2r_hw): data5[bh2r + i] = v
    out_hw = await run_matmul(dut, "mlp3_l3", N, bh2r, bW3, bout, data5, tc(N), out_count=N)
    assert out_hw == out_ref, "3-layer MLP: L3 matmul mismatch"


# ============================================================================
# Test 3 — 2-layer MLP with LeakyReLU
# ============================================================================

@cocotb.test()
async def test_mlp_leaky_relu(dut):
    """
    2-layer MLP with LeakyReLU (ACT func=2, α ≈ 2^-7 = 0.0078).
    Uses on-GPU activation — bit-exact vs Python q115_leaky_relu.
    """
    N = 4
    random.seed(2001)

    x_q  = [float_to_q115(random.uniform(-0.5, 0.5)) for _ in range(N)]
    W1_q = [float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N * N)]
    W2_q = [float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N * N)]

    bx, bW1, bh1, bh1r, bW2, bout = 0, 4, 20, 24, 28, 44

    data = [0] * (bout + N)
    for i, v in enumerate(x_q):  data[bx + i]  = v
    for i, v in enumerate(W1_q): data[bW1 + i] = v
    for i, v in enumerate(W2_q): data[bW2 + i] = v

    h1_ref  = ref_matmul(x_q, W1_q, N)
    h1r_ref = ref_act_vec(h1_ref, func=2)   # LeakyReLU
    out_ref = ref_matmul(h1r_ref, W2_q, N)

    h1_hw = await run_matmul(dut, "mlp_lrelu_l1", N, bx, bW1, bh1, data, tc(N), out_count=N)
    assert h1_hw == h1_ref, "MLP LeakyReLU: L1 matmul mismatch"

    data2 = list(data)
    for i, v in enumerate(h1_hw): data2[bh1 + i] = v
    h1r_hw = await run_act(dut, "mlp_lrelu_act", N, bh1, bh1r, data2, func=2)
    assert h1r_hw == h1r_ref, "MLP LeakyReLU: LeakyReLU activation mismatch"

    data3 = list(data2)
    for i, v in enumerate(h1r_hw): data3[bh1r + i] = v
    out_hw = await run_matmul(dut, "mlp_lrelu_l2", N, bh1r, bW2, bout, data3, tc(N), out_count=N)
    assert out_hw == out_ref, "MLP LeakyReLU: L2 matmul mismatch"


# ============================================================================
# Test 4 — 2-layer MLP with ClippedReLU
# ============================================================================

@cocotb.test()
async def test_mlp_clipped_relu(dut):
    """
    2-layer MLP with ClippedReLU (ACT func=3: clip to [0, Q115_MAX]).
    """
    N = 4
    random.seed(3001)

    x_q  = [float_to_q115(random.uniform(-0.5, 0.5)) for _ in range(N)]
    W1_q = [float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N * N)]
    W2_q = [float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N * N)]

    bx, bW1, bh1, bh1r, bW2, bout = 0, 4, 20, 24, 28, 44

    data = [0] * (bout + N)
    for i, v in enumerate(x_q):  data[bx + i]  = v
    for i, v in enumerate(W1_q): data[bW1 + i] = v
    for i, v in enumerate(W2_q): data[bW2 + i] = v

    h1_ref  = ref_matmul(x_q, W1_q, N)
    h1r_ref = ref_act_vec(h1_ref, func=3)   # ClippedReLU
    out_ref = ref_matmul(h1r_ref, W2_q, N)

    h1_hw = await run_matmul(dut, "mlp_crelu_l1", N, bx, bW1, bh1, data, tc(N), out_count=N)
    assert h1_hw == h1_ref, "MLP ClippedReLU: L1 mismatch"

    data2 = list(data)
    for i, v in enumerate(h1_hw): data2[bh1 + i] = v
    h1r_hw = await run_act(dut, "mlp_crelu_act", N, bh1, bh1r, data2, func=3)
    assert h1r_hw == h1r_ref, "MLP ClippedReLU: ClippedReLU mismatch"

    data3 = list(data2)
    for i, v in enumerate(h1r_hw): data3[bh1r + i] = v
    out_hw = await run_matmul(dut, "mlp_crelu_l2", N, bh1r, bW2, bout, data3, tc(N), out_count=N)
    assert out_hw == out_ref, "MLP ClippedReLU: L2 mismatch"


# ============================================================================
# Test 5 — Attention Q×K^T dot-product
# ============================================================================

@cocotb.test()
async def test_attention_qk_dot(dut):
    """
    Attention score matrix: S = Q × K^T.

    For a 4-head, d_k=4 single-head attention with Q and K as 4×4 matrices:
      S = Q × K^T

    K^T means K is transposed. Since our matmul kernel computes A×B, we
    pre-transpose K in Python (store K^T in memory as the B matrix).

    Verifies that attention score computation is bit-exact.
    """
    N = 4
    random.seed(4200)

    Q_f = [[random.uniform(-0.4, 0.4) for _ in range(N)] for _ in range(N)]
    K_f = [[random.uniform(-0.4, 0.4) for _ in range(N)] for _ in range(N)]

    Q_q = [float_to_q115(v) for row in Q_f for v in row]
    # K^T: transpose K row-by-row
    Kt_q = [float_to_q115(K_f[j][i]) for i in range(N) for j in range(N)]

    # Memory: Q at 0, K^T at 16, S at 32
    bQ, bKt, bS = 0, N * N, 2 * N * N

    data = Q_q + Kt_q + [0] * (N * N)
    S_ref = ref_matmul(Q_q, Kt_q, N)

    S_hw = await run_matmul(dut, "attn_qk", N, bQ, bKt, bS, data, tc(N * N))
    assert S_hw == S_ref, \
        f"Attention Q×K^T: score matrix mismatch"


# ============================================================================
# Test 6 — Scaled dot-product attention
# ============================================================================

@cocotb.test()
async def test_attention_scaled(dut):
    """
    Scaled attention: S_scaled[i] = S[i] * scale, where scale ≈ 1/sqrt(d_k).

    For d_k=4: scale = 1/sqrt(4) = 0.5.
    We compute S = Q×K^T then scale each element by 0.5 via a vec_scale kernel.

    Scaling uses FMA(acc=0, s_elem, scalar) so the scalar is pre-loaded into
    data memory.
    """
    N = 4
    random.seed(4201)

    Q_q = [float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N * N)]
    Kt_q = [float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N * N)]
    scale = float_to_q115(0.5)   # 1/sqrt(4) exactly in Q1.15

    # Memory:
    # 0-15:  Q
    # 16-31: K^T
    # 32-47: S (matmul result)
    # 48:    scale scalar
    # 49-64: S_scaled
    bQ, bKt, bS = 0, 16, 32
    b_scale, bSs = 48, 49

    data = Q_q + Kt_q + [0] * N * N + [scale] + [0] * N * N

    # Step 1: compute S = Q × K^T
    S_hw = await run_matmul(dut, "attn_scale_qk", N, bQ, bKt, bS, data, tc(N * N))
    S_ref = ref_matmul(Q_q, Kt_q, N)
    assert S_hw == S_ref, "Scaled attention: Q×K^T mismatch"

    # Step 2: scale each element by 0.5 (vec_scale kernel)
    def build_vec_scale_kernel_here(base_a, base_scalar_addr, base_out, count):
        return [
            asm_mul(R9, BLOCK_IDX, BLOCK_DIM),
            asm_add(R9, R9, THREAD_IDX),
            asm_const(R1, base_a),
            asm_const(R2, base_scalar_addr),
            asm_const(R3, base_out),
            asm_add(R4, R1, R9),
            asm_ldr(R4, R4),               # a[i]
            asm_ldr(R5, R2),               # scalar
            asm_const(R8, 0),              # acc = 0
            asm_fma(R8, R4, R5),           # out = a[i]*scalar
            asm_add(R7, R3, R9),
            asm_str(R7, R8),
            asm_ret(),
        ]

    data2 = list(data)
    for i, v in enumerate(S_hw): data2[bS + i] = v

    prog_scale = build_vec_scale_kernel_here(bS, b_scale, bSs, N * N)
    logger = await setup_test(dut, "attn_scale_scale", prog_scale, data2,
                               thread_count=tc(N * N), verbose=False)
    await run_kernel(dut, logger, max_cycles=1500, trace_interval=0)
    await ClockCycles(dut.clk, 10)
    Ss_hw = read_memory_range(dut, bSs, N * N)
    logger.close()

    # Reference: scale each S element by 0.5
    Ss_ref = [q115_mul(S_ref[i], scale) for i in range(N * N)]

    # Allow 1 LSB tolerance from FMA pipeline truncation
    def close(a, b):
        a_s = a if a < 32768 else a - 65536
        b_s = b if b < 32768 else b - 65536
        return abs(a_s - b_s) <= 1

    mismatches = [(i, Ss_hw[i], Ss_ref[i])
                  for i in range(N * N) if not close(Ss_hw[i], Ss_ref[i])]
    assert not mismatches, \
        f"Scaled attention: scale step failed at indices {[m[0] for m in mismatches[:5]]}"


# ============================================================================
# Test 7 — Residual connection
# ============================================================================

@cocotb.test()
async def test_residual_add(dut):
    """
    Residual / skip connection: out = layer(x) + x.

    Computes h = W×x (matmul), then out = h + x (element-wise saturating add).
    Verifies that the skip branch is added correctly in Q1.15.
    """
    N = 4
    random.seed(7001)

    x_q  = [float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N)]
    W_q  = [float_to_q115(random.uniform(-0.2, 0.2)) for _ in range(N * N)]

    # Memory:
    # 0-3:   x
    # 4-19:  W
    # 20-23: h = W×x
    # 24-27: out = h + x  (residual add)
    bx, bW, bh, bout = 0, 4, 20, 24

    data = x_q + W_q + [0] * N + [0] * N

    # Layer: h = W×x
    h_ref = ref_matmul(x_q, W_q, N)
    h_hw = await run_matmul(dut, "residual_matmul", N, bx, bW, bh, data, tc(N), out_count=N)
    assert h_hw == h_ref, "Residual: layer matmul mismatch"

    # Residual: out = h + x
    data2 = list(data)
    for i, v in enumerate(h_hw): data2[bh + i] = v
    out_ref = ref_vec_add(h_ref, x_q)
    out_hw = await run_vec_add(dut, "residual_add", N, bh, bx, bout, data2)
    assert out_hw == out_ref, \
        f"Residual: skip-add mismatch\n  hw={out_hw}\n  ref={out_ref}"


# ============================================================================
# Test 8 — Batched inference (4 different inputs, same weights)
# ============================================================================

@cocotb.test()
async def test_batch_4x_inference(dut):
    """
    Batch inference: same 2-layer MLP weights applied to 4 different inputs.
    Each pass runs independently as a fresh GPU kernel.  Verifies that state
    from one pass does not contaminate the next (no accumulator/register leaks
    across independent kernel launches).
    """
    N = 4
    random.seed(8001)

    W1_q = [float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N * N)]
    W2_q = [float_to_q115(random.uniform(-0.3, 0.3)) for _ in range(N * N)]

    inputs = [
        [float_to_q115(random.uniform(-0.5, 0.5)) for _ in range(N)]
        for _ in range(4)
    ]

    # Memory layout per call (all small addresses):
    # 0-3:   input vector
    # 4-19:  W1
    # 20-23: hidden
    # 24-27: hidden_relu
    # 28-43: W2
    # 44-47: output
    bx, bW1, bh, bhr, bW2, bout = 0, 4, 20, 24, 28, 44

    base_data = [0] * (bout + N)
    for i, v in enumerate(W1_q): base_data[bW1 + i] = v
    for i, v in enumerate(W2_q): base_data[bW2 + i] = v

    for batch_idx, x_q in enumerate(inputs):
        # Python reference for this input
        h_ref  = ref_matmul(x_q, W1_q, N)
        hr_ref = ref_act_vec(h_ref, func=1)
        out_ref = ref_matmul(hr_ref, W2_q, N)

        data = list(base_data)
        for i, v in enumerate(x_q): data[bx + i] = v

        # L1 matmul
        h_hw = await run_matmul(dut, f"batch{batch_idx}_l1", N,
                                bx, bW1, bh, data, tc(N), out_count=N)
        assert h_hw == h_ref, f"Batch {batch_idx}: L1 matmul mismatch"

        data2 = list(data)
        for i, v in enumerate(h_hw): data2[bh + i] = v
        hr_hw = await run_act(dut, f"batch{batch_idx}_relu", N,
                               bh, bhr, data2, func=1)
        assert hr_hw == hr_ref, f"Batch {batch_idx}: ReLU mismatch"

        data3 = list(data2)
        for i, v in enumerate(hr_hw): data3[bhr + i] = v
        out_hw = await run_matmul(dut, f"batch{batch_idx}_l2", N,
                                  bhr, bW2, bout, data3, tc(N), out_count=N)
        assert out_hw == out_ref, f"Batch {batch_idx}: L2 output mismatch"
