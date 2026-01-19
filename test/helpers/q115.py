"""
Q1.15 Fixed-Point Conversion Utilities

Q1.15 format:
- 1 sign bit (bit 15)
- 15 fractional bits (bits 14:0)
- Range: [-1.0, +0.999969...]
- Resolution: 2^-15 ≈ 0.0000305
"""

def float_to_q115(f: float) -> int:
    """
    Convert a floating-point number to Q1.15 fixed-point representation.
    
    Args:
        f: Float value in range [-1.0, 1.0)
        
    Returns:
        16-bit Q1.15 representation as unsigned integer
    """
    # Clamp to valid Q1.15 range
    f = max(-1.0, min(f, 32767 / 32768))
    
    # Convert to Q1.15 (multiply by 2^15 = 32768)
    q = int(round(f * 32768))
    
    # Handle negative numbers (two's complement)
    if q < 0:
        q = q + 65536  # Convert to unsigned 16-bit
    
    return q & 0xFFFF


def q115_to_float(q: int) -> float:
    """
    Convert a Q1.15 fixed-point value to floating-point.
    
    Args:
        q: 16-bit Q1.15 value (unsigned integer representation)
        
    Returns:
        Float value in range [-1.0, 1.0)
    """
    # Handle as signed 16-bit
    if q & 0x8000:  # Negative (sign bit set)
        return (q - 65536) / 32768.0
    return q / 32768.0


def q115_mul(a: int, b: int) -> int:
    """
    Multiply two Q1.15 values and return Q1.15 result.
    
    Args:
        a: First Q1.15 operand
        b: Second Q1.15 operand
        
    Returns:
        Q1.15 product
    """
    # Convert to signed
    a_signed = a if a < 32768 else a - 65536
    b_signed = b if b < 32768 else b - 65536
    
    # Multiply (result is Q2.30)
    product = a_signed * b_signed
    
    # Shift right 15 to get Q1.15
    result = product >> 15
    
    # Saturate to Q1.15 range
    if result > 32767:
        result = 32767
    elif result < -32768:
        result = -32768
    
    # Convert back to unsigned
    if result < 0:
        result = result + 65536
    
    return result & 0xFFFF


def q115_add(a: int, b: int) -> int:
    """
    Add two Q1.15 values with saturation.
    
    Args:
        a: First Q1.15 operand
        b: Second Q1.15 operand
        
    Returns:
        Q1.15 sum (saturated)
    """
    # Convert to signed
    a_signed = a if a < 32768 else a - 65536
    b_signed = b if b < 32768 else b - 65536
    
    # Add
    result = a_signed + b_signed
    
    # Saturate
    if result > 32767:
        result = 32767
    elif result < -32768:
        result = -32768
    
    # Convert back to unsigned
    if result < 0:
        result = result + 65536
    
    return result & 0xFFFF


def q115_fma(acc: int, a: int, b: int) -> int:
    """
    Fused multiply-add: acc + (a * b) in Q1.15.
    
    Args:
        acc: Accumulator Q1.15 value
        a: First multiplicand Q1.15
        b: Second multiplicand Q1.15
        
    Returns:
        Q1.15 result of acc + (a * b)
    """
    product = q115_mul(a, b)
    return q115_add(acc, product)


def q115_sub(a: int, b: int) -> int:
    """
    Subtract two Q1.15 values with saturation: a - b.
    
    Args:
        a: First Q1.15 operand
        b: Second Q1.15 operand (subtracted)
        
    Returns:
        Q1.15 difference (saturated)
    """
    # Convert to signed
    a_signed = a if a < 32768 else a - 65536
    b_signed = b if b < 32768 else b - 65536
    
    # Subtract
    result = a_signed - b_signed
    
    # Saturate
    if result > 32767:
        result = 32767
    elif result < -32768:
        result = -32768
    
    # Convert back to unsigned
    if result < 0:
        result = result + 65536
    
    return result & 0xFFFF


# =============================================================================
# Activation Functions
# =============================================================================

# Q1.15 Constants
Q115_ZERO = 0x0000
Q115_MAX = 0x7FFF  # +0.99997
Q115_MIN = 0x8000  # -1.0


def q115_relu(x: int) -> int:
    """
    ReLU activation: max(0, x) in Q1.15.
    
    Args:
        x: Q1.15 input value
        
    Returns:
        Q1.15 ReLU output (0 if negative, x if positive)
    """
    if x & 0x8000:  # Negative (sign bit set)
        return Q115_ZERO
    return x


def q115_leaky_relu(x: int, alpha_shift: int = 7) -> int:
    """
    Leaky ReLU: x if x > 0, else alpha * x in Q1.15.
    Uses right shift to approximate alpha (default ~0.0078 for shift=7).
    
    Args:
        x: Q1.15 input value
        alpha_shift: Right shift amount (7 gives ~0.0078, close to 0.01)
        
    Returns:
        Q1.15 Leaky ReLU output
    """
    if x & 0x8000:  # Negative
        # Convert to signed, shift right, convert back
        x_signed = x - 65536
        result = x_signed >> alpha_shift
        if result < 0:
            result = result + 65536
        return result & 0xFFFF
    return x


def q115_clipped_relu(x: int, max_val: int = Q115_MAX) -> int:
    """
    Clipped ReLU: min(max_val, max(0, x)) in Q1.15.
    
    Args:
        x: Q1.15 input value
        max_val: Maximum output value (default Q1.15 max)
        
    Returns:
        Q1.15 Clipped ReLU output
    """
    if x & 0x8000:  # Negative
        return Q115_ZERO
    return min(x, max_val)


def q115_sigmoid_approx(x: int) -> int:
    """
    Approximate sigmoid using piecewise linear approximation.
    sigmoid(x) ≈ 0.5 + 0.25*x for x in [-2, 2], clamped to [0, 1).
    
    Note: This is a rough approximation suitable for some applications.
    
    Args:
        x: Q1.15 input value
        
    Returns:
        Q1.15 approximate sigmoid output
    """
    x_signed = x if x < 32768 else x - 65536
    
    # Linear approximation: 0.5 + 0.25*x
    # In Q1.15: 0.5 = 0x4000, 0.25 = 0x2000
    half = 0x4000  # 0.5 in Q1.15
    quarter = x_signed >> 2  # x * 0.25
    
    result = (half >> 15) * 32768 + quarter  # Normalize back
    result = half + quarter
    
    # Clamp to [0, Q115_MAX]
    if result < 0:
        result = 0
    elif result > Q115_MAX:
        result = Q115_MAX
    
    # Convert to unsigned
    if result < 0:
        result = result + 65536
    
    return result & 0xFFFF


def q115_activation(x: int, func: int, bias: int = 0) -> int:
    """
    Apply activation function with optional bias in Q1.15.
    
    Args:
        x: Q1.15 input value
        func: Activation function code (0=none, 1=ReLU, 2=LeakyReLU, 3=ClippedReLU)
        bias: Optional bias to add before activation
        
    Returns:
        Q1.15 activated output
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
    Matrix multiplication C = A × B in Q1.15.
    
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
    Square matrix multiplication C = A × B in Q1.15.
    
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
    Dot product of two Q1.15 vectors.
    
    Args:
        a: First vector as list of Q1.15 values
        b: Second vector as list of Q1.15 values
        
    Returns:
        Q1.15 dot product result
    """
    assert len(a) == len(b), "Vectors must have same length"
    
    acc = 0
    for i in range(len(a)):
        acc = q115_fma(acc, a[i], b[i])
    
    return acc


def q115_vector_add(a: list, b: list) -> list:
    """
    Element-wise vector addition in Q1.15.
    
    Args:
        a: First vector as list of Q1.15 values
        b: Second vector as list of Q1.15 values
        
    Returns:
        Result vector
    """
    assert len(a) == len(b), "Vectors must have same length"
    return [q115_add(a[i], b[i]) for i in range(len(a))]


def q115_vector_scale(a: list, s: int) -> list:
    """
    Scale vector by Q1.15 scalar.
    
    Args:
        a: Vector as list of Q1.15 values
        s: Q1.15 scalar
        
    Returns:
        Scaled vector
    """
    return [q115_mul(a[i], s) for i in range(len(a))]


def q115_apply_activation_vector(x: list, func: int) -> list:
    """
    Apply activation function to each element of a vector.
    
    Args:
        x: Vector as list of Q1.15 values
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
    Create a Q1.15 matrix from float values.
    
    Args:
        floats: 2D list of float values
        rows: Number of rows
        cols: Number of columns
        
    Returns:
        2D list of Q1.15 values
    """
    return [[float_to_q115(floats[i][j]) for j in range(cols)] for i in range(rows)]


def q115_matrix_to_float(matrix: list) -> list:
    """
    Convert Q1.15 matrix to float matrix.
    
    Args:
        matrix: 2D list of Q1.15 values
        
    Returns:
        2D list of float values
    """
    return [[q115_to_float(v) for v in row] for row in matrix]


def create_identity_q115(n: int) -> list:
    """
    Create an NxN identity matrix in Q1.15.
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
    Check if two Q1.15 matrices are equal within tolerance.
    
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
    Format a Q1.15 matrix for display.
    
    Args:
        matrix: 2D list of Q1.15 values
        name: Matrix name for header
        
    Returns:
        Formatted string
    """
    lines = [f"{name}:"]
    for row in matrix:
        values = [f"{q115_to_float(v):+.4f}" for v in row]
        lines.append(f"  [{', '.join(values)}]")
    return '\n'.join(lines)
