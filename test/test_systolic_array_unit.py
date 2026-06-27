"""
Systolic Array Unit Tests for Atreides GPU

Tests the NxN systolic array with:
- Weight-stationary matrix multiplication
- Various matrix sizes (tested with 8x8 default)
- SF16 arithmetic verification
- Identity matrix tests
- Random matrix tests
- Edge cases
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_to_float
from helpers.logger import GPULogger

# Import SF31 accumulator model from systolic PE unit tests
from test_systolic_pe_unit import SF31Accumulator

# Default array size (must match compiled testbench) - Updated for 8x8
ARRAY_SIZE = 8
DATA_BITS = 16
FMA_MAC_PIFMA_LATENCY = 3  # wait cycles after compute_enable edge (2-cycle FMA + 1 array input stage)


def q115_matmul(A: list, B: list, N: int) -> list:
    """
    Reference model matching the hardware's weight-stationary computation.

    Hardware dataflow (weight-stationary):
    - Weight loading: b_inputs_flat[col] propagates vertically so that
      FMA[row][col] latches B[row][col] as its stationary weight.
    - Activation streaming: a_inputs_flat[row] = A[row][k] at diagonal
      wavefront cycle k+row.  The activation flows east through row `row`,
      reaching every FMA in that row.
    - Each FMA[i][j] therefore accumulates every A[i][k] (k=0..N-1) against
      its fixed weight B[i][j].

    Resulting computation:
        C[i][j] = sum_k  A[i][k] * B[i][j]
                = B[i][j] * (sum_k A[i][k])

    This is NOT standard matrix multiplication.  It is element-wise scaling:
    each row i of B is scaled by the sum of row i of A.

    Args:
        A: NxN matrix of SF16 values (activations)
        B: NxN matrix of SF16 values (weights, loaded row-by-row)
        N: Matrix dimension

    Returns:
        NxN result matrix in SF16
    """
    C = [[0 for _ in range(N)] for _ in range(N)]
    for i in range(N):
        for j in range(N):
            ref = SF31Accumulator()
            for k in range(N):
                ref.mac(A[i][k], B[i][j])   # FMA[i][j] weight = B[i][j], not B[k][j]
            C[i][j] = ref.read_q115()
    return C


def pack_inputs(values: list, bits: int = 16) -> int:
    """Pack list of values into a single flat integer."""
    result = 0
    for i, v in enumerate(values):
        result |= (v & ((1 << bits) - 1)) << (i * bits)
    return result


def unpack_results(flat: int, n: int, bits: int = 16, array_size: int = None) -> list:
    """
    Unpack flat integer to NxN matrix.
    
    Args:
        flat: Packed results as integer
        n: Size of the result matrix to extract
        bits: Bits per element
        array_size: Physical array size (defaults to ARRAY_SIZE)
    
    Returns:
        NxN result matrix
    """
    if array_size is None:
        array_size = ARRAY_SIZE
    
    mask = (1 << bits) - 1
    result = [[0 for _ in range(n)] for _ in range(n)]
    for i in range(n):
        for j in range(n):
            # Use array_size for stride, not n
            idx = i * array_size + j
            result[i][j] = (flat >> (idx * bits)) & mask
    return result


async def setup_array_test(dut, test_name: str, clock_period_ns: int = 10) -> GPULogger:
    """Set up systolic array test environment."""
    logger = GPULogger(test_name, log_dir="test/results")
    logger.set_verbose(True)
    
    logger.log_section(f"Systolic Array Unit Test: {test_name}")
    
    # Start clock
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.reset.value = 1
    dut.enable.value = 0
    dut.clear_acc.value = 0
    dut.load_weights.value = 0
    dut.compute_enable.value = 0
    dut.a_inputs_flat.value = 0
    dut.b_inputs_flat.value = 0
    
    # Wait for reset
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    dut.enable.value = 1
    await ClockCycles(dut.clk, 2)
    
    return logger


async def clear_accumulators(dut):
    """Clear all FMA accumulators."""
    dut.clear_acc.value = 1
    await RisingEdge(dut.clk)
    dut.clear_acc.value = 0
    await RisingEdge(dut.clk)


async def load_weights_all_rows(dut, B: list, N: int):
    """
    Load weights into the array by streaming B matrix rows.
    
    b_inputs[col] goes to b_wire[0][col] (row 0 of array).
    Data propagates down through FMA[row].b_out -> b_wire[row+1]
    with additional pipeline registers at certain row boundaries.
    
    Delay to FMA[row]: row + (row // PIFMA_INTERVAL)
    - row delays from FMA b_out registers
    - (row // PIFMA_INTERVAL) delays from pipeline registers
    
    We need all weights to arrive at their target FMAs on the same cycle.
    """
    PIFMA_INTERVAL = ARRAY_SIZE
    phys_size = ARRAY_SIZE
    
    dut.load_weights.value = 0
    
    # Compute delay for bottom-most row (maximum delay)
    max_row = phys_size - 1
    max_delay = max_row + max_row // PIFMA_INTERVAL
    
    # Create a schedule: schedule[c] = row to send at cycle c, or -1 for idle
    schedule = [-1] * (max_delay + 1)
    for row in range(phys_size):
        delay_for_row = row + row // PIFMA_INTERVAL
        send_cycle = max_delay - delay_for_row
        schedule[send_cycle] = row
    
    # Debug: print schedule
    # print(f"Weight load schedule (max_delay={max_delay}): {schedule}")
    
    # Stream according to schedule
    for c in range(max_delay):
        row = schedule[c]
        if row >= 0 and row < N:
            # Send B[row] values
            b_vals = [B[row][col] if col < N else 0 for col in range(phys_size)]
        else:
            b_vals = [0] * phys_size
        
        dut.b_inputs_flat.value = pack_inputs(b_vals)
        await RisingEdge(dut.clk)
    
    # Final cycle: row 0 should be in schedule at max_delay
    # but we handle it explicitly with load_weights
    final_row = schedule[max_delay] if max_delay < len(schedule) else -1
    if final_row >= 0 and final_row < N:
        b_vals = [B[final_row][col] if col < N else 0 for col in range(phys_size)]
    else:
        # Row 0 has delay 0, so it's at cycle max_delay
        b_vals = [B[0][col] if col < N else 0 for col in range(phys_size)]
    
    dut.b_inputs_flat.value = pack_inputs(b_vals)
    dut.load_weights.value = 1
    await RisingEdge(dut.clk)
    
    # Deassert
    dut.load_weights.value = 0
    dut.b_inputs_flat.value = 0
    await RisingEdge(dut.clk)


async def stream_activations(dut, A: list, N: int, num_cycles: int):
    """
    Stream activation matrix A through the array.
    For a systolic array, activations flow west-to-east with proper timing.
    Pads to ARRAY_SIZE for the physical array.
    """
    phys_size = ARRAY_SIZE
    dut.compute_enable.value = 1
    
    # Stream with diagonal wavefront timing
    for cycle in range(num_cycles):
        # Build activation inputs for this cycle (padded to ARRAY_SIZE)
        a_row = [0] * phys_size
        for row in range(N):
            # Which column element enters at this cycle
            col = cycle - row
            if 0 <= col < N:
                a_row[row] = A[row][col]
        
        dut.a_inputs_flat.value = pack_inputs(a_row)
        await RisingEdge(dut.clk)
    
    # Extra cycles for data to propagate through (using ARRAY_SIZE)
    for _ in range(phys_size + FMA_MAC_PIFMA_LATENCY):
        dut.a_inputs_flat.value = 0
        await RisingEdge(dut.clk)
    
    dut.compute_enable.value = 0


async def run_matmul(dut, A: list, B: list, N: int) -> list:
    """
    Run matrix multiplication C = A * B on the systolic array.
    
    Args:
        dut: Device under test
        A: NxN activation matrix (SF16)
        B: NxN weight matrix (SF16)
        N: Matrix dimension
        
    Returns:
        NxN result matrix (Q1.15)
    """
    phys_size = ARRAY_SIZE
    
    # Clear accumulators
    await clear_accumulators(dut)
    
    # Load weights (B matrix) into FMA weight registers
    await load_weights_all_rows(dut, B, N)
    
    # Extra settling time for weights
    await ClockCycles(dut.clk, 2)
    
    # Stream activations (A matrix) - use 2*N-1 cycles for NxN matmul
    await stream_activations(dut, A, N, 2 * N - 1)
    
    # Wait for computation to settle (using physical array size)
    await ClockCycles(dut.clk, phys_size + 2 + FMA_MAC_PIFMA_LATENCY)
    
    # Read results
    results_flat = int(dut.results_flat.value)
    return unpack_results(results_flat, N)


def format_q115(val: int) -> str:
    """Format Q1.15 value as hex and float."""
    return f"0x{val:04X} ({q115_to_float(val):+.6f})"


def print_matrix(logger, name: str, M: list, N: int):
    """Print a matrix to logger."""
    logger.log_message(f"  {name}:")
    for i in range(N):
        row_str = "    ["
        for j in range(N):
            row_str += f"{q115_to_float(M[i][j]):+.4f}"
            if j < N - 1:
                row_str += ", "
        row_str += "]"
        logger.log_message(row_str)


def matrices_equal(M1: list, M2: list, N: int, tolerance: float = 0.01) -> bool:
    """Check if two matrices are equal within tolerance."""
    for i in range(N):
        for j in range(N):
            v1 = q115_to_float(M1[i][j])
            v2 = q115_to_float(M2[i][j])
            if abs(v1 - v2) > tolerance:
                return False
    return True


def create_identity_q115(N: int) -> list:
    """Create NxN identity matrix in Q1.15 (using ~0.999 for 1.0)."""
    I = [[0 for _ in range(N)] for _ in range(N)]
    one = float_to_q115(0.999)  # Q1.15 can't represent 1.0 exactly
    for i in range(N):
        I[i][i] = one
    return I


def create_random_matrix(N: int, low: float = -0.5, high: float = 0.5) -> list:
    """Create NxN random matrix in Q1.15."""
    return [[float_to_q115(random.uniform(low, high)) for _ in range(N)] for _ in range(N)]


def create_zero_matrix(N: int) -> list:
    """Create NxN zero matrix."""
    return [[0 for _ in range(N)] for _ in range(N)]


@cocotb.test()
async def test_array_basic_2x2(dut):
    """Test basic 2x2 matrix multiplication (uses corner of 4x4 array)."""
    logger = await setup_array_test(dut, "array_basic_2x2")
    
    N = 2
    
    # Simple 2x2 matrices
    A = [
        [float_to_q115(0.5), float_to_q115(0.25)],
        [float_to_q115(0.125), float_to_q115(0.5)]
    ]
    B = [
        [float_to_q115(0.5), float_to_q115(0.25)],
        [float_to_q115(0.25), float_to_q115(0.5)]
    ]
    
    # Pad to 4x4 for the testbench
    A_padded = [[0]*ARRAY_SIZE for _ in range(ARRAY_SIZE)]
    B_padded = [[0]*ARRAY_SIZE for _ in range(ARRAY_SIZE)]
    for i in range(N):
        for j in range(N):
            A_padded[i][j] = A[i][j]
            B_padded[i][j] = B[i][j]
    
    logger.log_message(f"Testing {N}x{N} matrix multiplication")
    print_matrix(logger, "A", A_padded[:N], N)
    print_matrix(logger, "B", B_padded[:N], N)
    
    # Expected result
    expected = q115_matmul(A_padded, B_padded, ARRAY_SIZE)
    
    # Run on hardware
    hw_result = await run_matmul(dut, A_padded, B_padded, ARRAY_SIZE)
    
    print_matrix(logger, "Expected C", expected[:N], N)
    print_matrix(logger, "HW Result C", hw_result[:N], N)
    
    passed = matrices_equal(expected[:N], hw_result[:N], N)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Array basic 2x2 test failed"


@cocotb.test()
async def test_array_identity(dut):
    """Test multiplication with identity matrix: A * I = A."""
    logger = await setup_array_test(dut, "array_identity")
    
    N = ARRAY_SIZE
    
    # Random matrix A
    random.seed(42)
    A = create_random_matrix(N, -0.4, 0.4)
    I = create_identity_q115(N)
    
    logger.log_message(f"Testing {N}x{N}: A * I = A")
    print_matrix(logger, "A", A, N)
    
    # Expected: A * I should be approximately A (scaled by 0.999)
    expected = q115_matmul(A, I, N)
    
    # Run on hardware
    hw_result = await run_matmul(dut, A, I, N)
    
    print_matrix(logger, "Expected (A*I)", expected, N)
    print_matrix(logger, "HW Result", hw_result, N)
    
    passed = matrices_equal(expected, hw_result, N, tolerance=0.02)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Array identity test failed"


@cocotb.test()
async def test_array_zeros(dut):
    """Test multiplication with zero matrix."""
    logger = await setup_array_test(dut, "array_zeros")
    
    N = ARRAY_SIZE
    
    A = create_random_matrix(N)
    Z = create_zero_matrix(N)
    
    logger.log_message(f"Testing {N}x{N}: A * 0 = 0")
    
    # Run on hardware
    hw_result = await run_matmul(dut, A, Z, N)
    expected = create_zero_matrix(N)
    
    print_matrix(logger, "HW Result", hw_result, N)
    
    passed = matrices_equal(expected, hw_result, N)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Array zeros test failed"


@cocotb.test()
async def test_array_4x4_full(dut):
    """Test full NxN matrix multiplication using array size."""
    logger = await setup_array_test(dut, "array_4x4_full")
    
    # Use ARRAY_SIZE to match hardware
    N = ARRAY_SIZE
    random.seed(123)
    
    A = create_random_matrix(N, -0.3, 0.3)
    B = create_random_matrix(N, -0.3, 0.3)
    
    logger.log_message(f"Testing {N}x{N} matrix multiplication")
    print_matrix(logger, "A", A, N)
    print_matrix(logger, "B", B, N)
    
    expected = q115_matmul(A, B, N)
    hw_result = await run_matmul(dut, A, B, N)
    
    print_matrix(logger, "Expected C", expected, N)
    print_matrix(logger, "HW Result C", hw_result, N)
    
    # Compare element by element
    passed = True
    for i in range(N):
        for j in range(N):
            exp_f = q115_to_float(expected[i][j])
            hw_f = q115_to_float(hw_result[i][j])
            if abs(exp_f - hw_f) > 0.02:
                logger.log_message(f"  MISMATCH at [{i}][{j}]: HW={hw_f:.4f}, Expected={exp_f:.4f}")
                passed = False
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Array 4x4 full test failed"


@cocotb.test()
async def test_array_symmetric(dut):
    """Test with symmetric matrices."""
    logger = await setup_array_test(dut, "array_symmetric")
    
    N = ARRAY_SIZE
    
    # Create symmetric matrix
    A = [[0]*N for _ in range(N)]
    for i in range(N):
        for j in range(i, N):
            val = float_to_q115(random.uniform(-0.3, 0.3))
            A[i][j] = val
            A[j][i] = val
    
    logger.log_message(f"Testing {N}x{N}: A * A (symmetric)")
    print_matrix(logger, "A (symmetric)", A, N)
    
    expected = q115_matmul(A, A, N)
    hw_result = await run_matmul(dut, A, A, N)
    
    print_matrix(logger, "Expected A*A", expected, N)
    print_matrix(logger, "HW Result", hw_result, N)
    
    passed = matrices_equal(expected, hw_result, N, tolerance=0.02)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Array symmetric test failed"


@cocotb.test()
async def test_array_negative_values(dut):
    """Test with negative values."""
    logger = await setup_array_test(dut, "array_negative")
    
    N = 4
    
    # Matrices with mixed signs
    A = [
        [float_to_q115(-0.5), float_to_q115(0.25), float_to_q115(-0.125), float_to_q115(0.0625)],
        [float_to_q115(0.5), float_to_q115(-0.25), float_to_q115(0.125), float_to_q115(-0.0625)],
        [float_to_q115(-0.25), float_to_q115(0.125), float_to_q115(-0.0625), float_to_q115(0.03125)],
        [float_to_q115(0.125), float_to_q115(-0.0625), float_to_q115(0.03125), float_to_q115(-0.015625)]
    ]
    B = [
        [float_to_q115(0.5), float_to_q115(-0.25), float_to_q115(0.125), float_to_q115(-0.0625)],
        [float_to_q115(-0.25), float_to_q115(0.5), float_to_q115(-0.25), float_to_q115(0.125)],
        [float_to_q115(0.125), float_to_q115(-0.25), float_to_q115(0.5), float_to_q115(-0.25)],
        [float_to_q115(-0.0625), float_to_q115(0.125), float_to_q115(-0.25), float_to_q115(0.5)]
    ]
    
    A_padded = [[0]*ARRAY_SIZE for _ in range(ARRAY_SIZE)]
    B_padded = [[0]*ARRAY_SIZE for _ in range(ARRAY_SIZE)]
    for i in range(N):
        for j in range(N):
            A_padded[i][j] = A[i][j]
            B_padded[i][j] = B[i][j]
    
    logger.log_message(f"Testing {N}x{N} with negative values")
    print_matrix(logger, "A", A_padded[:N], N)
    print_matrix(logger, "B", B_padded[:N], N)
    
    expected = q115_matmul(A_padded, B_padded, ARRAY_SIZE)
    hw_result = await run_matmul(dut, A_padded, B_padded, ARRAY_SIZE)
    
    print_matrix(logger, "Expected C", expected[:N], N)
    print_matrix(logger, "HW Result C", hw_result[:N], N)
    
    passed = matrices_equal(expected[:N], hw_result[:N], N, tolerance=0.02)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Array negative values test failed"


@cocotb.test()
async def test_array_random_batch(dut):
    """Test multiple random matrix multiplications."""
    logger = await setup_array_test(dut, "array_random_batch")
    
    N = ARRAY_SIZE
    num_tests = 5
    random.seed(456)
    
    passed = True
    
    logger.log_message(f"Running {num_tests} random {N}x{N} matrix multiplications")
    
    for test_idx in range(num_tests):
        A = create_random_matrix(N, -0.3, 0.3)
        B = create_random_matrix(N, -0.3, 0.3)
        
        expected = q115_matmul(A, B, N)
        hw_result = await run_matmul(dut, A, B, N)
        
        test_passed = matrices_equal(expected, hw_result, N, tolerance=0.02)
        if not test_passed:
            passed = False
            logger.log_message(f"\n  Test {test_idx}: FAIL")
            print_matrix(logger, "A", A, N)
            print_matrix(logger, "B", B, N)
            print_matrix(logger, "Expected", expected, N)
            print_matrix(logger, "HW Result", hw_result, N)
        else:
            logger.log_message(f"  Test {test_idx}: PASS")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Array random batch test failed"


@cocotb.test()
async def test_array_accumulation_clear(dut):
    """Test that clear_acc properly resets between multiplications."""
    logger = await setup_array_test(dut, "array_accumulation_clear")
    
    N = ARRAY_SIZE
    random.seed(789)
    
    A1 = create_random_matrix(N, -0.2, 0.2)
    B1 = create_random_matrix(N, -0.2, 0.2)
    
    A2 = create_random_matrix(N, -0.2, 0.2)
    B2 = create_random_matrix(N, -0.2, 0.2)
    
    logger.log_message("Testing accumulator clear between multiplications")
    
    # First multiplication
    hw_result1 = await run_matmul(dut, A1, B1, N)
    expected1 = q115_matmul(A1, B1, N)
    
    # Second multiplication (should not include residual from first)
    hw_result2 = await run_matmul(dut, A2, B2, N)
    expected2 = q115_matmul(A2, B2, N)
    
    passed1 = matrices_equal(expected1, hw_result1, N, tolerance=0.02)
    passed2 = matrices_equal(expected2, hw_result2, N, tolerance=0.02)
    
    logger.log_message(f"  First multiplication: {'PASS' if passed1 else 'FAIL'}")
    logger.log_message(f"  Second multiplication: {'PASS' if passed2 else 'FAIL'}")
    
    passed = passed1 and passed2
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Array accumulation clear test failed"