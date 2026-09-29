"""
Bit-exact reference for the chip's IEEE-style 16-bit formats (FP16, BF16).

Semantics shared with src/fp_arith.sv:
  - fused multiply-add: the exact a*b + c is rounded once (round to nearest,
    ties to even)
  - flush to zero: subnormal inputs read as signed zero; a result whose exact
    magnitude is below the smallest normal becomes a signed zero (tininess is
    detected before rounding)
  - overflow after rounding gives signed infinity
  - NaN in, inf*0, or inf-inf gives the canonical quiet NaN (sign 0)
  - zero signs follow IEEE 754 round-to-nearest: an exact zero sum of
    non-zero terms is +0; 0 + 0 is -0 only if both zeros are -0
"""
from fractions import Fraction


class Fmt:
    def __init__(self, name, exp_bits, mant_bits):
        self.name = name
        self.e = exp_bits
        self.m = mant_bits
        self.bias = (1 << (exp_bits - 1)) - 1
        self.emax_field = (1 << exp_bits) - 1
        self.emin = 1 - self.bias                 # unbiased exponent of the smallest normal
        self.emax = self.emax_field - 1 - self.bias
        self.qnan = (self.emax_field << mant_bits) | (1 << (mant_bits - 1))
        self.width = 1 + exp_bits + mant_bits

    # ---------------------------------------------------------------- decode
    def decode(self, bits):
        """-> (kind, sign, value) with kind in zero/num/inf/nan; value is a Fraction."""
        bits &= 0xFFFF
        s = bits >> (self.width - 1)
        ef = (bits >> self.m) & self.emax_field
        f = bits & ((1 << self.m) - 1)
        if ef == self.emax_field:
            return ("nan", 0, None) if f else ("inf", s, None)
        if ef == 0:
            return ("zero", s, Fraction(0))           # subnormals flush to zero
        v = Fraction((1 << self.m) | f, 1 << self.m) * Fraction(2) ** (ef - self.bias)
        return ("num", s, -v if s else v)

    def to_float(self, bits):
        kind, s, v = self.decode(bits)
        if kind == "nan":
            return float("nan")
        if kind == "inf":
            return float("-inf") if s else float("inf")
        if kind == "zero":
            return -0.0 if s else 0.0
        return float(v)

    # ---------------------------------------------------------------- encode
    def zero(self, sign):
        return (sign & 1) << (self.width - 1)

    def inf(self, sign):
        return ((sign & 1) << (self.width - 1)) | (self.emax_field << self.m)

    def round_exact(self, v):
        """Round a non-zero exact Fraction with RNE, FTZ and overflow to inf."""
        s = 1 if v < 0 else 0
        a = -v if s else v
        # exponent of the leading bit
        e = a.numerator.bit_length() - a.denominator.bit_length()
        if Fraction(2) ** e > a:
            e -= 1
        elif Fraction(2) ** (e + 1) <= a:
            e += 1
        if e < self.emin:
            return self.zero(s)                       # tiny before rounding: flush
        scaled = a / Fraction(2) ** (e - self.m)      # in [2^m, 2^(m+1))
        q, r = divmod(scaled.numerator, scaled.denominator)
        rem = Fraction(r, scaled.denominator)
        if rem > Fraction(1, 2) or (rem == Fraction(1, 2) and (q & 1)):
            q += 1
        if q == (1 << (self.m + 1)):                  # rounding carried out
            q >>= 1
            e += 1
        if e > self.emax:
            return self.inf(s)
        ef = e + self.bias
        return (s << (self.width - 1)) | (ef << self.m) | (q & ((1 << self.m) - 1))

    def from_float(self, x):
        """Nearest representable value (RNE, FTZ) for building test data."""
        if x != x:
            return self.qnan
        if x in (float("inf"), float("-inf")):
            return self.inf(1 if x < 0 else 0)
        if x == 0:
            return self.zero(1 if str(x).startswith("-") else 0)
        return self.round_exact(Fraction(x))

    # ---------------------------------------------------------------- ops
    def fma(self, a, b, c):
        """round(a*b + c), the operation every multiply-accumulate in the chip performs."""
        ka, sa, va = self.decode(a)
        kb, sb, vb = self.decode(b)
        kc, sc, vc = self.decode(c)
        sp = sa ^ sb
        if "nan" in (ka, kb, kc):
            return self.qnan
        p_inf = ka == "inf" or kb == "inf"
        p_zero = ka == "zero" or kb == "zero"
        if p_inf and p_zero:
            return self.qnan                          # inf * 0
        if p_inf and kc == "inf" and sp != sc:
            return self.qnan                          # inf - inf
        if p_inf:
            return self.inf(sp)
        if kc == "inf":
            return self.inf(sc)
        prod = Fraction(0) if p_zero else va * vb
        total = prod + (vc if kc == "num" else Fraction(0))
        if total == 0:
            if p_zero and kc == "zero":
                return self.zero(sp & sc)
            return self.zero(0)                       # exact cancellation
        return self.round_exact(total)

    def add(self, a, b):
        return self.fma(a, self.one(), b)

    def one(self):
        return self.bias << self.m

    LEAKY_SHIFT = 7

    def act(self, x, bias, func):
        """ACT: f(round(x + bias)), matching src/fp_activation.sv.

        func 0 none, 1 ReLU, 2 Leaky ReLU (negative inputs times 2^-7, exact,
        -0 below the smallest normal), 3 clipped ReLU (NaN kept, else
        min(1.0, ReLU)).
        """
        y = self.add(x, bias)
        s = y >> (self.width - 1)
        ef = (y >> self.m) & self.emax_field
        is_nan = ef == self.emax_field and (y & ((1 << self.m) - 1))
        if func == 0:
            return y
        if func == 1:
            return 0 if s else y
        if func == 2:
            if not s or ef == self.emax_field:
                return y
            if ef > self.LEAKY_SHIFT:
                return y - (self.LEAKY_SHIFT << self.m)
            return self.zero(1)
        if is_nan:
            return y
        if s:
            return 0
        return min(y, self.one())

    def pe_accumulate(self, activations, weight):
        """A systolic PE after a clear: acc = round(a * w + acc) per compute."""
        acc = 0
        for a in activations:
            acc = self.fma(a, weight, acc)
        return acc


FP16 = Fmt("fp16", 5, 10)
BF16 = Fmt("bf16", 8, 7)
FORMATS = {"fp16": FP16, "bf16": BF16}
BY_ID = {1: FP16, 2: BF16}      # NUMBER_FORMAT parameter values; 0 is SF16
