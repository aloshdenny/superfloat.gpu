"""
SF16 (Superfloat 16-bit) Fixed-Point Conversion Utilities

SF16 format (sign-magnitude):
- 1 sign bit (bit 15)
- 15 mantissa bits (bits 14:0)
- Value: x = (-1)^s · m / 2^15,  m ∈ {0, 1, ..., 2^15 - 1}
- Range: [-0.999969..., +0.999969...]  (symmetric)
- Resolution: 2^-15 ≈ 0.0000305

Negative zero canonicalization:
  0x8000 (sign=1, mantissa=0) is negative zero and must be
  forced to 0x0000 (positive zero) in all paths.

Product format:
  SF16 × SF16 = SF31 (1 sign bit + 30 mantissa bits)
  The two sign bits coalesce via XOR into a single product sign bit.
"""


def sf16_canonicalize(q: int) -> int:
    """
    Canonicalize an SF16 value: force negative zero (0x8000) to positive zero (0x0000).

    Args:
        q: 16-bit SF16 value

    Returns:
        Canonicalized SF16 value
    """
    q = q & 0xFFFF
    if q == 0x8000:
        return 0x0000
    return q


def float_to_q115(f: float) -> int:
    """
    Convert a floating-point number to SF16 (sign-magnitude) representation.

    Args:
        f: Float value in range [-0.999969..., +0.999969...]

    Returns:
        16-bit SF16 representation as unsigned integer
    """
    # Clamp to valid SF16 range (symmetric: ±32767/32768)
    f = max(-32767 / 32768, min(f, 32767 / 32768))

    # Sign-magnitude encoding
    if f < 0:
        sign = 1
        mantissa = int(round(-f * 32768))
    else:
        sign = 0
        mantissa = int(round(f * 32768))

    # Clamp mantissa to 15-bit range
    mantissa = min(mantissa, 0x7FFF)

    result = (sign << 15) | mantissa
    return sf16_canonicalize(result)


def q115_to_float(q: int) -> float:
    """
    Convert an SF16 (sign-magnitude) value to floating-point.

    Args:
        q: 16-bit SF16 value (unsigned integer representation)

    Returns:
        Float value in range [-0.999969..., +0.999969...]
    """
    q = sf16_canonicalize(q)
    sign = (q >> 15) & 1
    mantissa = q & 0x7FFF
    value = mantissa / 32768.0
    if sign:
        value = -value
    return value


def _sf16_to_signed(q: int) -> int:
    """Convert SF16 sign-magnitude to Python signed integer (mantissa with sign)."""
    q = sf16_canonicalize(q)
    sign = (q >> 15) & 1
    mantissa = q & 0x7FFF
    return -mantissa if sign else mantissa


def _signed_to_sf16(val: int) -> int:
    """Convert Python signed integer back to SF16 sign-magnitude with saturation."""
    if val < 0:
        mantissa = min(-val, 0x7FFF)
        result = 0x8000 | mantissa
    else:
        mantissa = min(val, 0x7FFF)
        result = mantissa
    return sf16_canonicalize(result)


def q115_mul(a: int, b: int) -> int:
    """
    Multiply two SF16 values and return SF16 result.

    Product: SF16 × SF16 = SF31 (1 sign + 30 mantissa bits).
    The 30-bit mantissa product is right-shifted by 15 to produce SF16.

    Args:
        a: First SF16 operand
        b: Second SF16 operand

    Returns:
        SF16 product
    """
    a = sf16_canonicalize(a)
    b = sf16_canonicalize(b)

    # Extract sign and magnitude
    sign_a = (a >> 15) & 1
    sign_b = (b >> 15) & 1
    mag_a = a & 0x7FFF
    mag_b = b & 0x7FFF

    # Product sign (XOR of input signs)
    sign_product = sign_a ^ sign_b

    # Unsigned mantissa multiply: 15-bit × 15-bit = 30-bit (SF31 mantissa)
    product = mag_a * mag_b

    # Shift right 15 to get SF16 mantissa
    result_mag = product >> 15

    # Saturate to 15-bit mantissa range
    if result_mag > 0x7FFF:
        result_mag = 0x7FFF

    # Reconstruct SF16
    result = (sign_product << 15) | result_mag
    return sf16_canonicalize(result)


def q115_add(a: int, b: int) -> int:
    """
    Add two SF16 values with saturation.

    Internally converts to signed representation for addition,
    then converts back to SF16 sign-magnitude.

    Args:
        a: First SF16 operand
        b: Second SF16 operand

    Returns:
        SF16 sum (saturated)
    """
    a_signed = _sf16_to_signed(a)
    b_signed = _sf16_to_signed(b)

    result = a_signed + b_signed

    return _signed_to_sf16(result)


def q115_fma(acc: int, a: int, b: int) -> int:
    """
    Fused multiply-add: acc + (a * b) in SF16.

    Args:
        acc: Accumulator SF16 value
        a: First multiplicand SF16
        b: Second multiplicand SF16

    Returns:
        SF16 result of acc + (a * b)
    """
    product = q115_mul(a, b)
    return q115_add(acc, product)


def q115_sub(a: int, b: int) -> int:
    """
    Subtract two SF16 values with saturation: a - b.

    Args:
        a: First SF16 operand
        b: Second SF16 operand (subtracted)

    Returns:
        SF16 difference (saturated)
    """
    a_signed = _sf16_to_signed(a)
    b_signed = _sf16_to_signed(b)

    result = a_signed - b_signed

    return _signed_to_sf16(result)


# =============================================================================
# Activation Functions
# =============================================================================

# SF16 Constants
Q115_ZERO = 0x0000
Q115_MAX = 0x7FFF  # +0.999969... (max positive: sign=0, mantissa=0x7FFF)
Q115_MIN = 0xFFFF  # -0.999969... (max negative: sign=1, mantissa=0x7FFF)


def q115_relu(x: int) -> int:
    """
    ReLU activation: max(0, x) in SF16.

    Args:
        x: SF16 input value

    Returns:
        SF16 ReLU output (0 if negative, x if positive)
    """
    x = sf16_canonicalize(x)
    if x & 0x8000:  # Negative (sign bit set)
        return Q115_ZERO
    return x


def q115_leaky_relu(x: int, alpha_shift: int = 7) -> int:
    """
    Leaky ReLU: x if x > 0, else alpha * x in SF16.
    Uses right shift to approximate alpha (default ~0.0078 for shift=7).

    Args:
        x: SF16 input value
        alpha_shift: Right shift amount (7 gives ~0.0078, close to 0.01)

    Returns:
        SF16 Leaky ReLU output
    """
    x = sf16_canonicalize(x)
    if x & 0x8000:  # Negative
        # Extract mantissa, shift right (reduce magnitude), keep sign
        mantissa = x & 0x7FFF
        reduced_mantissa = mantissa >> alpha_shift
        if reduced_mantissa == 0:
            return Q115_ZERO
        return 0x8000 | reduced_mantissa
    return x


def q115_clipped_relu(x: int, max_val: int = Q115_MAX) -> int:
    """
    Clipped ReLU: min(max_val, max(0, x)) in SF16.

    Args:
        x: SF16 input value
        max_val: Maximum output value (default SF16 max)

    Returns:
        SF16 Clipped ReLU output
    """
    x = sf16_canonicalize(x)
    if x & 0x8000:  # Negative
        return Q115_ZERO
    return min(x, max_val)


def q115_sigmoid_approx(x: int) -> int:
    """
    Approximate sigmoid using piecewise linear approximation.
    sigmoid(x) ≈ 0.5 + 0.25*x for x in [-2, 2], clamped to [0, 1).

    Note: This is a rough approximation suitable for some applications.

    Args:
        x: SF16 input value

    Returns:
        SF16 approximate sigmoid output
    """
    x_signed = _sf16_to_signed(x)

    # Linear approximation: 0.5 + 0.25*x
    # In SF16: 0.5 = 0x4000, 0.25 = 0x2000
    half = 0x4000  # 0.5 in SF16
    quarter = x_signed >> 2  # x * 0.25

    result = half + quarter

    # Clamp to [0, Q115_MAX]
    if result < 0:
        result = 0
    elif result > Q115_MAX:
        result = Q115_MAX

    return result & 0xFFFF


def q115_activation(x: int, func: int, bias: int = 0) -> int:
    """
    Apply activation function with optional bias in SF16.

    Args:
        x: SF16 input value
        func: Activation function code (0=none, 1=ReLU, 2=LeakyReLU, 3=ClippedReLU)
        bias: Optional bias to add before activation

    Returns:
        SF16 activated output
    """
    # Add bias first
    if bias != 0:
        x = q115_add(x, bias)

    # Apply activation
    if func == 0:  # None
        return x
    elif func == 1:  # ReLU
        return q115_relu(x)
    elif func == 2:  # Leaky ReLU
        return q115_leaky_relu(x)
    elif func == 3:  # Clipped ReLU
        return q115_clipped_relu(x)
    else:
        return x


# =============================================================================
# Matrix Operations
# =============================================================================

def q115_matmul(A: list, B: list, M: int, N: int, K: int) -> list:
    """
    Matrix multiplication C = A × B in SF16.

    Args:
        A: M×K matrix as flat list (row-major)
        B: K×N matrix as flat list (row-major)
        M: Number of rows in A
        N: Number of columns in B
        K: Number of columns in A / rows in B

    Returns:
        M×N result matrix as flat list (row-major)
    """
    C = [0] * (M * N)

    for i in range(M):
        for j in range(N):
            acc = 0
            for k in range(K):
                a_val = A[i * K + k]
                b_val = B[k * N + j]
                acc = q115_fma(acc, a_val, b_val)
            C[i * N + j] = acc

    return C


def q115_matmul_2d(A: list, B: list) -> list:
    """
    Square matrix multiplication C = A × B in SF16.

    Args:
        A: NxN matrix as 2D list
        B: NxN matrix as 2D list

    Returns:
        NxN result matrix as 2D list
    """
    N = len(A)
    C = [[0 for _ in range(N)] for _ in range(N)]

    for i in range(N):
        for j in range(N):
            acc = 0
            for k in range(N):
                acc = q115_fma(acc, A[i][k], B[k][j])
            C[i][j] = acc

    return C


def q115_dot_product(a: list, b: list) -> int:
    """
    Dot product of two SF16 vectors.

    Args:
        a: First vector as list of SF16 values
        b: Second vector as list of SF16 values

    Returns:
        SF16 dot product result
    """
    assert len(a) == len(b), "Vectors must have same length"

    acc = 0
    for i in range(len(a)):
        acc = q115_fma(acc, a[i], b[i])

    return acc


def q115_vector_add(a: list, b: list) -> list:
    """
    Element-wise vector addition in SF16.

    Args:
        a: First vector as list of SF16 values
        b: Second vector as list of SF16 values

    Returns:
        Result vector
    """
    assert len(a) == len(b), "Vectors must have same length"
    return [q115_add(a[i], b[i]) for i in range(len(a))]


def q115_vector_scale(a: list, s: int) -> list:
    """
    Scale vector by SF16 scalar.

    Args:
        a: Vector as list of SF16 values
        s: SF16 scalar

    Returns:
        Scaled vector
    """
    return [q115_mul(a[i], s) for i in range(len(a))]


def q115_apply_activation_vector(x: list, func: int) -> list:
    """
    Apply activation function to each element of a vector.

    Args:
        x: Vector as list of SF16 values
        func: Activation function code

    Returns:
        Activated vector
    """
    return [q115_activation(v, func) for v in x]


# =============================================================================
# Utility Functions
# =============================================================================

def create_q115_matrix(floats: list, rows: int, cols: int) -> list:
    """
    Create an SF16 matrix from float values.

    Args:
        floats: 2D list of float values
        rows: Number of rows
        cols: Number of columns

    Returns:
        2D list of SF16 values
    """
    return [[float_to_q115(floats[i][j]) for j in range(cols)] for i in range(rows)]


def q115_matrix_to_float(matrix: list) -> list:
    """
    Convert SF16 matrix to float matrix.

    Args:
        matrix: 2D list of SF16 values

    Returns:
        2D list of float values
    """
    return [[q115_to_float(v) for v in row] for row in matrix]


def create_identity_q115(n: int) -> list:
    """
    Create an NxN identity matrix in SF16.
    Note: Uses 0.999... (Q115_MAX) for diagonal since 1.0 is not representable.

    Args:
        n: Matrix dimension

    Returns:
        NxN identity matrix as 2D list
    """
    one = float_to_q115(0.9999)
    return [[one if i == j else 0 for j in range(n)] for i in range(n)]


def create_zero_matrix(rows: int, cols: int) -> list:
    """
    Create a zero matrix.

    Args:
        rows: Number of rows
        cols: Number of columns

    Returns:
        Zero matrix as 2D list
    """
    return [[0 for _ in range(cols)] for _ in range(rows)]


def q115_matrices_equal(A: list, B: list, tolerance: float = 0.001) -> bool:
    """
    Check if two SF16 matrices are equal within tolerance.

    Args:
        A: First matrix as 2D list
        B: Second matrix as 2D list
        tolerance: Maximum allowed difference in float representation

    Returns:
        True if matrices are equal within tolerance
    """
    if len(A) != len(B) or len(A[0]) != len(B[0]):
        return False

    for i in range(len(A)):
        for j in range(len(A[0])):
            diff = abs(q115_to_float(A[i][j]) - q115_to_float(B[i][j]))
            if diff > tolerance:
                return False

    return True


def format_q115_matrix(matrix: list, name: str = "Matrix") -> str:
    """
    Format an SF16 matrix for display.

    Args:
        matrix: 2D list of SF16 values
        name: Matrix name for header

    Returns:
        Formatted string
    """
    lines = [f"{name}:"]
    for row in matrix:
        values = [f"{q115_to_float(v):+.4f}" for v in row]
        lines.append(f"  [{', '.join(values)}]")
    return '\n'.join(lines)
