"""
SF16 vs IEEE fp32 Reference Implementations & Error Analysis

Provides:
- IEEE fp32 reference matmul for ground-truth comparison
- Per-element error analysis (absolute, relative, ULP)
- Formatted comparison reports for SF16 precision evaluation
"""

from .q115 import float_to_q115, q115_to_float, q115_matmul


# =============================================================================
# IEEE fp32 Reference Implementation
# =============================================================================

def ieee_fp32_matmul(A_q: list, B_q: list, M: int, N: int, K: int) -> list:
    """
    IEEE fp32 reference matmul from SF16 inputs.
    
    Converts SF16 inputs to float, performs fp32 matmul, returns float results.
    This is the "golden" reference — what infinite-precision math would give
    (modulo fp32 rounding, which is ~7 decimal digits).
    
    Args:
        A_q: M×K matrix as flat list of SF16 values
        B_q: K×N matrix as flat list of SF16 values
        M, N, K: Matrix dimensions
        
    Returns:
        M×N result as flat list of floats
    """
    C = [0.0] * (M * N)
    for i in range(M):
        for j in range(N):
            acc = 0.0
            for k in range(K):
                a_f = q115_to_float(A_q[i * K + k])
                b_f = q115_to_float(B_q[k * N + j])
                acc += a_f * b_f
            C[i * N + j] = acc
    return C


# =============================================================================
# Error Analysis
# =============================================================================

def q115_ulp_error(q115_val: int, fp32_val: float) -> float:
    """
    Compute error in ULPs (units in the last place) for SF16.
    
    One ULP in SF16 = 2^-15 ≈ 3.0518e-5.
    
    Args:
        q115_val: Hardware result in SF16
        fp32_val: IEEE fp32 reference result
        
    Returns:
        Error in ULPs (can be fractional)
    """
    ULP = 1.0 / 32768.0  # 2^-15
    hw_float = q115_to_float(q115_val)
    return abs(hw_float - fp32_val) / ULP


def q115_error_analysis(q115_results: list, fp32_results: list) -> dict:
    """
    Per-element error analysis: SF16 hardware vs IEEE fp32 reference.
    
    Args:
        q115_results: List of SF16 values from hardware
        fp32_results: List of fp32 reference values
        
    Returns:
        Dict with error metrics:
          - per_element: list of (hw_float, ref_float, abs_error, rel_error, ulp_error)
          - max_abs_error, mean_abs_error, rms_error
          - max_ulp_error, mean_ulp_error
          - num_elements, num_exact_matches
    """
    assert len(q115_results) == len(fp32_results), "Result length mismatch"
    n = len(q115_results)
    
    per_element = []
    abs_errors = []
    ulp_errors = []
    exact_matches = 0
    
    for i in range(n):
        hw_f = q115_to_float(q115_results[i])
        ref_f = fp32_results[i]
        
        abs_err = abs(hw_f - ref_f)
        rel_err = abs_err / abs(ref_f) if abs(ref_f) > 1e-10 else 0.0
        ulp_err = q115_ulp_error(q115_results[i], ref_f)
        
        # Check if SF16 quantization of fp32 reference matches hardware
        expected_q = float_to_q115(max(-1.0, min(ref_f, 32767 / 32768)))
        if q115_results[i] == expected_q:
            exact_matches += 1
        
        per_element.append((hw_f, ref_f, abs_err, rel_err, ulp_err))
        abs_errors.append(abs_err)
        ulp_errors.append(ulp_err)
    
    rms = (sum(e ** 2 for e in abs_errors) / n) ** 0.5 if n > 0 else 0.0
    
    return {
        'per_element': per_element,
        'max_abs_error': max(abs_errors) if abs_errors else 0.0,
        'mean_abs_error': sum(abs_errors) / n if n > 0 else 0.0,
        'rms_error': rms,
        'max_ulp_error': max(ulp_errors) if ulp_errors else 0.0,
        'mean_ulp_error': sum(ulp_errors) / n if n > 0 else 0.0,
        'num_elements': n,
        'num_exact_matches': exact_matches,
    }


def q115_vs_ieee_report(name: str, A_q: list, B_q: list, M: int, N: int, K: int,
                         hw_results: list) -> str:
    """
    Generate a formatted comparison report: SF16 HW vs IEEE fp32.
    
    Args:
        name: Test name
        A_q, B_q: Input matrices as flat SF16 lists
        M, N, K: Dimensions
        hw_results: Hardware SF16 results (flat list)
        
    Returns:
        Multi-line formatted report string
    """
    fp32_ref = ieee_fp32_matmul(A_q, B_q, M, N, K)
    analysis = q115_error_analysis(hw_results, fp32_ref)
    
    lines = [
        f"═══ SF16 vs IEEE fp32 Report: {name} ═══",
        f"Matrix: {M}×{K} × {K}×{N} → {M}×{N}",
        f"Elements: {analysis['num_elements']}",
        f"Exact SF16 matches: {analysis['num_exact_matches']}/{analysis['num_elements']}",
        "",
        f"Max absolute error:  {analysis['max_abs_error']:.6e}",
        f"Mean absolute error: {analysis['mean_abs_error']:.6e}",
        f"RMS error:           {analysis['rms_error']:.6e}",
        f"Max ULP error:       {analysis['max_ulp_error']:.2f}",
        f"Mean ULP error:      {analysis['mean_ulp_error']:.2f}",
        "",
        "Per-element detail:",
        f"{'Idx':>4} {'HW SF16':>10} {'IEEE fp32':>12} {'AbsErr':>12} {'ULP':>8}",
        "─" * 52,
    ]
    
    for i, (hw_f, ref_f, abs_err, rel_err, ulp_err) in enumerate(analysis['per_element']):
        flag = " ✓" if ulp_err < 1.5 else " ◆" if ulp_err < 3.0 else " ✗"
        lines.append(
            f"{i:4d} {hw_f:+10.6f} {ref_f:+12.8f} {abs_err:12.6e} {ulp_err:8.2f}{flag}"
        )
    
    lines.append("─" * 52)
    lines.append("Legend: ✓ <1.5 ULP  ◆ <3 ULP  ✗ ≥3 ULP")
    
    return "\n".join(lines)
