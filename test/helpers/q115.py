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

