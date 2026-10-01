"""
GPT-2 tensors as the chip's 16-bit words (numpy, Python 3.9 compatible).

SF16 is Q1.15 sign-magnitude in [-1, 1): each tensor is scaled by a power of
two so its largest magnitude fits, and the host keeps the exponent. FP16 and
BF16 round to nearest even and flush subnormals to signed zero, as the chip
does (helpers/fp16fmt.py).
"""
import math

import numpy as np

SF16, FP16, BF16 = 0, 1, 2
NAMES = {SF16: "sf16", FP16: "fp16", BF16: "bf16"}


def sf16_scale_exp(a: np.ndarray) -> int:
    """The power of two e with max|a| / 2**e < 1."""
    m = float(np.max(np.abs(a))) if a.size else 0.0
    return 0 if m < 1.0 else int(math.floor(math.log2(m))) + 1


def to_sf16(a: np.ndarray, exp: int = None) -> np.ndarray:
    if exp is None:
        exp = sf16_scale_exp(a)
    x = np.asarray(a, dtype=np.float64) / (2.0 ** exp)
    mag = np.minimum(np.rint(np.abs(x) * 32768.0), 32767).astype(np.uint32)
    words = np.where(x < 0, 0x8000 | mag, mag).astype(np.uint32)
    words[words == 0x8000] = 0                      # canonical zero
    return words.astype(np.uint16)


def to_fp16(a: np.ndarray) -> np.ndarray:
    h = np.asarray(a, dtype=np.float32).astype(np.float16).view(np.uint16)
    sub = (h & 0x7C00) == 0
    return np.where(sub, h & 0x8000, h).astype(np.uint16)


def to_bf16(a: np.ndarray) -> np.ndarray:
    b = np.asarray(a, dtype=np.float32).view(np.uint32).astype(np.uint64)
    r = ((b + 0x7FFF + ((b >> 16) & 1)) >> 16).astype(np.uint32)
    nan = np.isnan(np.asarray(a, dtype=np.float32))
    r = np.where(nan, 0x7FC0, r)
    sub = (r & 0x7F80) == 0
    return np.where(sub, r & 0x8000, r).astype(np.uint16)


def to_words(a: np.ndarray, fmt: int) -> np.ndarray:
    return {SF16: to_sf16, FP16: to_fp16, BF16: to_bf16}[fmt](a)
