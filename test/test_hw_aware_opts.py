"""
Hardware-aware optimization benches (software skip / bypass; no new ISA opcode).

Sparse: magnitude-prune weights, skip FMA when weight==0 via CMP+BRz.
Unity: when weight == SF16 max (+0x7FFF), bypass mul using ACT SF-add.

No trained ResNet-20 checkpoint is present in this repository. Matrices are
deterministic synthetic data so sparsity/unity rates are exact. Trained-model
unity/sparsity fractions are reported as UNAVAILABLE in the paper notes file.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import cocotb
from cocotb.triggers import ClockCycles

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_matmul, q115_fma, q115_add
from helpers.memory import (
    read_memory_range,
    asm_mul, asm_add, asm_sub, asm_div, asm_const, asm_ldr, asm_str, asm_fma,
    asm_cmp, asm_brn, asm_brz, asm_brnzp, asm_ret, asm_act,
    R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12,
    BLOCK_IDX, BLOCK_DIM, THREAD_IDX,
)
from helpers.setup import setup_test, run_kernel

RESULTS_PATH = Path(__file__).resolve().parent / "logs" / "hw_aware_opts_results.json"

Q_P1 = float_to_q115(1.0)   # 0x7FFF after clamp
Q_M1 = float_to_q115(-1.0)  # 0xFFFF style sign-mag max neg


def magnitude_prune_to_sparsity(weights_f, sparsity: float):
    """Element-wise magnitude prune (may diverge under SIMT BRz)."""
    n = len(weights_f)
    if n == 0 or sparsity == 0.0:
        return list(weights_f), 0.0
    order = sorted(range(n), key=lambda i: abs(weights_f[i]))
    n_zero = int(round(sparsity * n))
    pruned = list(weights_f)
    for i in order[:n_zero]:
        pruned[i] = 0.0
    actual = sum(1 for v in pruned if v == 0.0) / float(n)
    return pruned, actual


def structured_row_prune_B(B_f_2d, sparsity: float):
    """
    Zero whole rows of B (k-dimension) by ascending mean |row| until sparsity
    is met. All threads loading B[k][col] then see the same zero/nonzero at k,
    so CMP+BRz does not SIMT-diverge.
    """
    n = len(B_f_2d)
    rows = list(range(n))
    rows.sort(key=lambda r: sum(abs(v) for v in B_f_2d[r]) / float(n))
    n_zero_rows = int(round(sparsity * n))
    out = [list(row) for row in B_f_2d]
    for r in rows[:n_zero_rows]:
        out[r] = [0.0] * n
    flat = [v for row in out for v in row]
    actual = sum(1 for v in flat if v == 0.0) / float(n * n)
    return out, actual


def inject_plus1_fraction(weights_f, unity_frac: float):
    n = len(weights_f)
    n_u = int(round(unity_frac * n))
    out = list(weights_f)
    for i in range(n_u):
        out[i] = 32767 / 32768  # exact SF16 +max
    actual = sum(1 for v in out if abs(v - (32767 / 32768)) < 1e-15) / float(n)
    return out, actual


def q115_matmul_unity_bypass_ref(A, B, M, N, K, plus1_code=Q_P1):
    """Reference: FMA normally; if B[k,j]==plus1_code then acc = acc + A[i,k] (SF add)."""
    C = [0] * (M * N)
    for i in range(M):
        for j in range(N):
            acc = 0
            for k in range(K):
                a = A[i * K + k]
                b = B[k * N + j]
                if b == plus1_code:
                    acc = q115_add(acc, a)
                else:
                    acc = q115_fma(acc, a, b)
            C[i * N + j] = acc
    return C


def build_dense_matmul_program(N: int, base_a: int, base_b: int, base_c: int):
    return [
        asm_mul(R0, BLOCK_IDX, BLOCK_DIM),
        asm_add(R0, R0, THREAD_IDX),
        asm_const(R1, 1),
        asm_const(R2, N),
        asm_const(R3, base_a),
        asm_const(R4, base_b),
        asm_const(R5, base_c),
        asm_div(R6, R0, R2),
        asm_mul(R7, R6, R2),
        asm_sub(R7, R0, R7),
        asm_const(R8, 0),
        asm_const(R9, 0),
        # LOOP @12
        asm_mul(R10, R6, R2),
        asm_add(R10, R10, R9),
        asm_add(R10, R10, R3),
        asm_ldr(R10, R10),
        asm_mul(R11, R9, R2),
        asm_add(R11, R11, R7),
        asm_add(R11, R11, R4),
        asm_ldr(R11, R11),
        asm_fma(R8, R10, R11),  # 20
        asm_add(R9, R9, R1),
        asm_cmp(R9, R2),
        asm_brn(12 - 24),
        asm_add(R9, R5, R0),
        asm_str(R9, R8),
        asm_ret(),
    ]


def build_sparse_skip_matmul_program(N: int, base_a: int, base_b: int, base_c: int):
    """Skip FMA when weight (R11) == 0. R12 holds zero."""
    # 0-11 prologue with CONST R12,#0 at end of constants — need a free slot.
    # Use: after R9 init, set R12=0. That shifts LOOP.
    #
    # 0-9: same through col
    # 10 CONST R8,0
    # 11 CONST R9,0
    # 12 CONST R12,0
    # LOOP=13
    # 13-16 A
    # 17-20 B
    # 21 CMP R11, R12
    # 22 BRz 24
    # 23 FMA
    # 24 ADD k
    # 25 CMP k,N
    # 26 BRn LOOP  (13-27=-14)
    # 27-29 store/ret
    return [
        asm_mul(R0, BLOCK_IDX, BLOCK_DIM),
        asm_add(R0, R0, THREAD_IDX),
        asm_const(R1, 1),
        asm_const(R2, N),
        asm_const(R3, base_a),
        asm_const(R4, base_b),
        asm_const(R5, base_c),
        asm_div(R6, R0, R2),
        asm_mul(R7, R6, R2),
        asm_sub(R7, R0, R7),
        asm_const(R8, 0),
        asm_const(R9, 0),
        asm_const(R12, 0),
        # LOOP @13
        asm_mul(R10, R6, R2),
        asm_add(R10, R10, R9),
        asm_add(R10, R10, R3),
        asm_ldr(R10, R10),
        asm_mul(R11, R9, R2),
        asm_add(R11, R11, R7),
        asm_add(R11, R11, R4),
        asm_ldr(R11, R11),
        asm_cmp(R11, R12),       # 21
        asm_brz(24 - 23),        # 22 -> 24
        asm_fma(R8, R10, R11),   # 23
        asm_add(R9, R9, R1),     # 24
        asm_cmp(R9, R2),         # 25
        asm_brn(13 - 27),        # 26
        asm_add(R9, R5, R0),     # 27
        asm_str(R9, R8),         # 28
        asm_ret(),               # 29
    ]


def build_unity_bypass_matmul_program(N: int, base_a: int, base_b: int, base_c: int, addr_p1: int):
    """If weight == +max SF16 at addr_p1, ACT-add A into acc; else FMA."""
    assert addr_p1 < 256
    # LOOP @12
    # 12-19 loads
    # 20 CONST R12, addr_p1
    # 21 LDR R12,R12
    # 22 CMP R11,R12
    # 23 BRz 26
    # 24 FMA
    # 25 BR 27
    # 26 ACT R8 = R8 + R10  (asm_act(8,R8,R10))
    # 27 ADD k ...
    return [
        asm_mul(R0, BLOCK_IDX, BLOCK_DIM),
        asm_add(R0, R0, THREAD_IDX),
        asm_const(R1, 1),
        asm_const(R2, N),
        asm_const(R3, base_a),
        asm_const(R4, base_b),
        asm_const(R5, base_c),
        asm_div(R6, R0, R2),
        asm_mul(R7, R6, R2),
        asm_sub(R7, R0, R7),
        asm_const(R8, 0),
        asm_const(R9, 0),
        # LOOP @12
        asm_mul(R10, R6, R2),
        asm_add(R10, R10, R9),
        asm_add(R10, R10, R3),
        asm_ldr(R10, R10),
        asm_mul(R11, R9, R2),
        asm_add(R11, R11, R7),
        asm_add(R11, R11, R4),
        asm_ldr(R11, R11),
        asm_const(R12, addr_p1),
        asm_ldr(R12, R12),
        asm_cmp(R11, R12),
        asm_brz(26 - 24),
        asm_fma(R8, R10, R11),
        asm_brnzp(27 - 26),
        asm_act(8, R8, R10),
        asm_add(R9, R9, R1),
        asm_cmp(R9, R2),
        asm_brn(12 - 30),
        asm_add(R9, R5, R0),
        asm_str(R9, R8),
        asm_ret(),
    ]


def _flat(mat):
    return [v for row in mat for v in row]


async def _run_case(dut, name, program, data, n, thread_count, expected_c, max_cycles=8000):
    logger = await setup_test(
        dut, test_name=name, program=program, data=data,
        thread_count=thread_count, verbose=False,
    )
    cycles = await run_kernel(dut, logger, max_cycles=max_cycles, trace_interval=0)
    await ClockCycles(dut.clk, 5)
    got = read_memory_range(dut, 2 * n * n, n * n)
    ok = got == expected_c
    logger.close()
    return {
        "name": name,
        "cycles": int(cycles),
        "sim_time_ns_at_10ns_clk": int(cycles) * 10,
        "correct": bool(ok),
        "expected_head": [int(x) for x in expected_c[:4]],
        "got_head": [int(x) for x in got[:4]],
    }


@cocotb.test()
async def test_sparse_and_unity_matmul_benches(dut):
    N = 4
    base_a, base_b, base_c = 0, N * N, 2 * N * N
    addr_p1 = 3 * N * N
    thread_count = N * N

    A_f = [[((i * 3 + j) % 7) / 10.0 - 0.3 for j in range(N)] for i in range(N)]
    B_dense_f = [[((i * 5 + j * 2) % 9) / 12.0 - 0.35 for j in range(N)] for i in range(N)]

    results = {
        "notes": [
            "No ResNet-20 checkpoint in repo; synthetic deterministic matrices only.",
            "Simulation clock period is 10 ns (setup_test default); silicon STA uses 20 ns.",
            "Sparse skip: CMP+BRz around FMA when weight==0.",
            "Unity +1 bypass: ACT SF-add when weight==0x7FFF; not a true IEEE +1.0.",
        ],
        "N": N,
        "sparse": [],
        "unity": [],
        "resnet_like": [],
    }

    for sparsity in (0.0, 0.25, 0.50, 0.75):
        # Structured row prune (SIMT-safe). Also record that element-wise
        # magnitude prune + BRz is incorrect on this core (divergence).
        B_f, actual_sp = structured_row_prune_B(B_dense_f, sparsity)
        A_q = [float_to_q115(v) for v in _flat(A_f)]
        B_q = [float_to_q115(v) for v in _flat(B_f)]
        expected = q115_matmul(A_q, B_q, N, N, N)
        data = [0] * (3 * N * N + 2)
        for i, v in enumerate(A_q):
            data[base_a + i] = v
        for i, v in enumerate(B_q):
            data[base_b + i] = v
        data[addr_p1] = Q_P1

        total_fma_sites = N * N * N
        nonzero_apps = sum(
            1
            for row in range(N)
            for col in range(N)
            for k in range(N)
            if B_q[k * N + col] != 0
        )

        r_dense = await _run_case(
            dut, f"sparse_dense_sp{sparsity}",
            build_dense_matmul_program(N, base_a, base_b, base_c),
            data, N, thread_count, expected,
        )
        r_sparse = await _run_case(
            dut, f"sparse_skip_sp{sparsity}",
            build_sparse_skip_matmul_program(N, base_a, base_b, base_c),
            data, N, thread_count, expected,
        )
        results["sparse"].append({
            "prune_mode": "structured_B_rows",
            "target_sparsity": sparsity,
            "actual_sparsity": actual_sp,
            "zero_weight_entries": sum(1 for v in B_q if v == 0),
            "weight_entries": N * N,
            "fma_sites_dense": total_fma_sites,
            "nonzero_fma_applications": nonzero_apps,
            "effective_fma_utilization": nonzero_apps / float(total_fma_sites),
            "dense_kernel": r_dense,
            "sparse_skip_kernel": r_sparse,
            "cycle_delta_sparse_minus_dense": r_sparse["cycles"] - r_dense["cycles"],
        })

    # Document element-wise prune + BRz divergence failure (one point)
    ew_flat, ew_sp = magnitude_prune_to_sparsity(_flat(B_dense_f), 0.50)
    B_ew = [ew_flat[i * N:(i + 1) * N] for i in range(N)]
    A_q = [float_to_q115(v) for v in _flat(A_f)]
    B_q = [float_to_q115(v) for v in _flat(B_ew)]
    expected = q115_matmul(A_q, B_q, N, N, N)
    data = [0] * (3 * N * N + 2)
    for i, v in enumerate(A_q):
        data[base_a + i] = v
    for i, v in enumerate(B_q):
        data[base_b + i] = v
    r_ew = await _run_case(
        dut, "sparse_elementwise_brz_sp0.5_EXPECT_DIVERGE",
        build_sparse_skip_matmul_program(N, base_a, base_b, base_c),
        data, N, thread_count, expected,
    )
    results["sparse_elementwise_brz_divergence_demo"] = {
        "actual_sparsity": ew_sp,
        "correct": r_ew["correct"],
        "cycles": r_ew["cycles"],
        "note": "Element-wise zeros make lanes disagree on BRz; SIMT skip is unsafe.",
    }

    for unity_frac in (0.0, 0.25, 0.50, 0.75):
        flat_b = _flat(B_dense_f)
        unity_flat, actual_u = inject_plus1_fraction(flat_b, unity_frac)
        B_f = [unity_flat[i * N:(i + 1) * N] for i in range(N)]
        A_q = [float_to_q115(v) for v in _flat(A_f)]
        B_q = [float_to_q115(v) for v in _flat(B_f)]
        expected = q115_matmul_unity_bypass_ref(A_q, B_q, N, N, N, Q_P1)
        data = [0] * (3 * N * N + 2)
        for i, v in enumerate(A_q):
            data[base_a + i] = v
        for i, v in enumerate(B_q):
            data[base_b + i] = v
        data[addr_p1] = Q_P1

        r_dense = await _run_case(
            dut, f"unity_dense_u{unity_frac}",
            build_dense_matmul_program(N, base_a, base_b, base_c),
            data, N, thread_count, q115_matmul(A_q, B_q, N, N, N),
        )
        r_unity = await _run_case(
            dut, f"unity_bypass_u{unity_frac}",
            build_unity_bypass_matmul_program(N, base_a, base_b, base_c, addr_p1),
            data, N, thread_count, expected,
        )
        results["unity"].append({
            "target_unity_frac": unity_frac,
            "actual_unity_frac": actual_u,
            "plus1_q115_entries": sum(1 for v in B_q if v == Q_P1),
            "q115_plus1_code": Q_P1,
            "q115_minus1_code": Q_M1,
            "dense_kernel_vs_fma_ref": r_dense,
            "unity_bypass_kernel_vs_bypass_ref": r_unity,
            "cycle_delta_unity_minus_dense": r_unity["cycles"] - r_dense["cycles"],
            "note": "Dense kernel checked vs q115_matmul; bypass kernel vs add-on-+1 reference.",
        })

    # ResNet-like: 4x4 matmul at 50% structured sparsity
    B_f, actual_sp = structured_row_prune_B(B_dense_f, 0.50)
    A_q = [float_to_q115(v) for v in _flat(A_f)]
    B_q = [float_to_q115(v) for v in _flat(B_f)]
    expected = q115_matmul(A_q, B_q, N, N, N)
    data = [0] * (3 * N * N + 2)
    for i, v in enumerate(A_q):
        data[base_a + i] = v
    for i, v in enumerate(B_q):
        data[base_b + i] = v
    r_d = await _run_case(
        dut, "resnet_like_dense_sp0.5",
        build_dense_matmul_program(N, base_a, base_b, base_c),
        data, N, thread_count, expected,
    )
    r_s = await _run_case(
        dut, "resnet_like_sparse_sp0.5",
        build_sparse_skip_matmul_program(N, base_a, base_b, base_c),
        data, N, thread_count, expected,
    )
    results["resnet_like"].append({
        "description": "4x4 matmul step analogous to test_model_resnet conv-as-matmul; synthetic structured sparsity",
        "actual_sparsity": actual_sp,
        "dense": r_d,
        "sparse_skip": r_s,
        "cycle_delta": r_s["cycles"] - r_d["cycles"],
    })

    RESULTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    RESULTS_PATH.write_text(json.dumps(results, indent=2) + "\n")

    bad = []
    for block in results["sparse"]:
        if not block["dense_kernel"]["correct"] or not block["sparse_skip_kernel"]["correct"]:
            bad.append(block["target_sparsity"])
    for block in results["unity"]:
        if not block["dense_kernel_vs_fma_ref"]["correct"]:
            bad.append(("unity_dense", block["target_unity_frac"]))
        if not block["unity_bypass_kernel_vs_bypass_ref"]["correct"]:
            bad.append(("unity_bypass", block["target_unity_frac"]))
    for block in results["resnet_like"]:
        if not block["dense"]["correct"] or not block["sparse_skip"]["correct"]:
            bad.append("resnet_like")
    # element-wise divergence demo is expected to fail correctness
    assert not bad, f"Functional mismatches: {bad}"
    assert results["sparse_elementwise_brz_divergence_demo"]["correct"] is False, (
        "Expected element-wise BRz skip to fail under SIMT divergence"
    )
