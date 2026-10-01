"""
GPT-2 matrix kernels for the OpenFrame chip, and their bit-exact references.

Every matrix multiply of GPT-2 runs as one of two kernels. A launch covers up
to 31 thread blocks (the thread count is 8 bits); each block computes 8 output
columns on its tile's 8x8 array. The host maps each launch's operands into
the chip's 64K-word data window:

  TABLE (word 0)    3 words per block: x base, weight base, output base
  x, weights, out   anywhere above TABLE_WORDS, laid out in kernel order

Weights are stored in the order the kernel reads them, so every pointer steps
by 8 (one word per thread). The host holds the model in that order; nothing
is rearranged on the chip.

gemv: one token (decode). Row r of the array holds weight row k0+r and
  thread i drives x[k0+i], so each array compute is 64 MACs for 8 x words and
  64 weight words. After the K loop, thread j sums column j over the 8 rows
  (SYS read, ACT add) and stores y[j]. Bus reads per weight: 1.125.

gemm: 8 tokens (prefill). Every row holds weight row k (one broadcast SYS
  load) and thread i drives token i's x[k], so the array is an outer product
  per k. One paired LDR brings both words per thread. Thread i stores token
  i's 8 outputs. Bus reads per MAC: 0.25.

SYS load also takes the activation operand (R0), and an activation reaches
column c c + 1 cycles after it changes. gemv loads x with the first of eight
weight rows; gemm puts the pointer updates between its load and compute.
Either way every column has settled before the compute: no flush is needed
(see the SYS operand hold in src/core.sv).
"""
import os
import sys

_TEST_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, _TEST_DIR)
try:
    import cocotb  # noqa: F401
except ImportError:
    # Outside a simulation (prepare.py): helpers/__init__ imports cocotb, so
    # register the package path alone; the submodules used here do not.
    import types
    _pkg = types.ModuleType("helpers")
    _pkg.__path__ = [os.path.join(_TEST_DIR, "helpers")]
    sys.modules.setdefault("helpers", _pkg)
from helpers.memory import (                      # noqa: E402
    asm_const, asm_add, asm_ldr, asm_ldr2, asm_str, asm_act, asm_cmp, asm_brn, asm_ret,
    R0, R1, R2, R3, R4, R5, R6, R7, R9, R10, BLOCK_IDX, THREAD_IDX,
)
from helpers.addr import build_large_const          # noqa: E402
from helpers.q115 import q115_add                   # noqa: E402

N = 8
MAX_BLOCKS = 31                 # thread count is bus_in[7:0]
TABLE_WORDS = 3 * MAX_BLOCKS + 3
WINDOW_WORDS = 1 << 16


def sys_op(op: int, rd: int = 0, bcast: bool = False) -> int:
    """SYS op (00 clear, 01 load, 10 compute, 11 read into rd); array 0.
    bcast (load only, bit 5): every row takes this load's weights."""
    return (0xC << 12) | (rd << 8) | (op << 6) | (int(bcast) << 5)


SYS_CLEAR, SYS_LOAD, SYS_COMPUTE, SYS_READ = 0b00, 0b01, 0b10, 0b11


def _prologue() -> list:
    """R2 = x base + tid, R3 = weight base + tid, R9 = output base, R5 = 8."""
    return [
        asm_add(R6, BLOCK_IDX, BLOCK_IDX),
        asm_add(R6, R6, BLOCK_IDX),            # 3 * blockIdx
        asm_ldr(R2, R6),                       # x base
        asm_const(R7, 1),
        asm_add(R6, R6, R7),
        asm_ldr(R3, R6),                       # weight base
        asm_add(R6, R6, R7),
        asm_ldr(R9, R6),                       # output base
        asm_add(R2, R2, THREAD_IDX),
        asm_add(R3, R3, THREAD_IDX),
        asm_const(R5, N),
        asm_const(R0, 0),
        asm_const(R1, 0),
        sys_op(SYS_CLEAR),
    ]


def _loop_bound(kx: int) -> list:
    """R10 = R2 + kx: the x pointer one past the last step (R7 scratch)."""
    return build_large_const(R10, kx, scratch_reg=R7) + [asm_add(R10, R10, R2)]


def gemv_program(kc: int) -> list:
    """y[j] = sum_k x[k] W[k][j] for one token, K = kc (a multiple of 8)."""
    assert kc % N == 0 and kc >= N
    p = _prologue() + _loop_bound(kc)
    loop = len(p)
    p += [asm_ldr(R0, R2), asm_add(R2, R2, R5)]           # x[k0 + tid]
    for _ in range(N):                                      # rows 7..0
        p += [asm_ldr(R1, R3), sys_op(SYS_LOAD), asm_add(R3, R3, R5)]
    p += [sys_op(SYS_COMPUTE), asm_cmp(R2, R10)]
    p += [asm_brn(loop - (len(p) + 1))]
    assert len(p) - loop <= 32, "loop must fit the 32-entry instruction cache"
    # Column tid summed over the rows: cells tid, tid+8, ..., tid+56.
    p += [asm_const(R0, 0), asm_add(R0, R0, THREAD_IDX), sys_op(SYS_READ, rd=R4)]
    for _ in range(N - 1):
        p += [asm_add(R0, R0, R5), sys_op(SYS_READ, rd=R1), asm_act(R4, R4, R1)]
    p += [asm_add(R9, R9, THREAD_IDX), asm_str(R9, R4), asm_ret()]
    return p


def gemm_program(kc: int) -> list:
    """Y[i][j] = sum_k A[i][k] W[k][j] for 8 tokens, K = kc (even)."""
    assert kc % 2 == 0 and kc >= 2
    p = _prologue() + _loop_bound(N * kc)
    loop = len(p)
    for _ in range(4 if kc % 4 == 0 else 2):
        p += [asm_ldr2(R0, R2, R3),                            # A[tid][k], W[k][tid]
              sys_op(SYS_LOAD, bcast=True),                    # every row = W[k]
              asm_add(R2, R2, R5), asm_add(R3, R3, R5),        # (x settles meanwhile)
              sys_op(SYS_COMPUTE)]
    p += [asm_cmp(R2, R10)]
    p += [asm_brn(loop - (len(p) + 1))]
    assert len(p) - loop <= 32, "loop must fit the 32-entry instruction cache"
    # Thread tid stores token tid's row: cells 8*tid .. 8*tid + 7.
    p += [asm_const(R7, 1), asm_const(R0, 0)]
    for _ in range(N):
        p += [asm_add(R0, R0, THREAD_IDX)]                   # R0 = 8 * tid
    p += [asm_add(R9, R9, R0)]
    for _ in range(N):
        p += [sys_op(SYS_READ, rd=R4), asm_str(R9, R4),
              asm_add(R0, R0, R7), asm_add(R9, R9, R7)]
    p += [asm_ret()]
    return p


# ---------------------------------------------------------------------------
# Window layout
# ---------------------------------------------------------------------------

class Window:
    """A launch's data window: block table plus operand regions."""

    def __init__(self):
        self.data = {}
        self.top = TABLE_WORDS
        self.blocks = []                       # (x base, weight base, output base)

    def alloc(self, words: int) -> int:
        base = self.top
        self.top += words
        assert self.top <= WINDOW_WORDS, f"window overflow: {self.top} words"
        return base

    def alloc_x(self, words: int) -> int:
        """An x/A region: the loop bound is a signed compare, so it must not
        cross 0x8000."""
        base = self.alloc(words)
        assert base + words <= 0x8000 or base >= 0x8000, "x region crosses 0x8000"
        return base

    def put(self, base: int, words) -> None:
        for i, w in enumerate(words):
            self.data[base + i] = w

    def add_block(self, x_base: int, w_base: int, y_base: int) -> None:
        b = len(self.blocks)
        assert b < MAX_BLOCKS
        self.blocks.append((x_base, w_base, y_base))
        self.data[3 * b], self.data[3 * b + 1], self.data[3 * b + 2] = x_base, w_base, y_base


def gemv_weight_words(W, col0: int) -> list:
    """Kernel order of W[:, col0:col0+8] for gemv: per k block, rows 7..0."""
    kc = len(W)
    out = []
    for k0 in range(0, kc, N):
        for r in reversed(range(N)):
            out += [W[k0 + r][col0 + i] for i in range(N)]
    return out


def gemm_weight_words(W, col0: int) -> list:
    """Kernel order of W[:, col0:col0+8] for gemm: per k, columns 0..7."""
    return [W[k][col0 + i] for k in range(len(W)) for i in range(N)]


def gemm_act_words(A) -> list:
    """Kernel order of A (8 tokens x K) for gemm: per k, tokens 0..7."""
    kc = len(A[0])
    return [A[i][k] for k in range(kc) for i in range(N)]


# ---------------------------------------------------------------------------
# Bit-exact references (16-bit words in the chip's format)
# ---------------------------------------------------------------------------

def _sf16_step(acc: int, a: int, w: int) -> int:
    """One systolic_pe accumulate: acc is two's complement, a/w SF16."""
    a = 0 if (a & 0xFFFF) == 0x8000 else a & 0xFFFF
    w = 0 if (w & 0xFFFF) == 0x8000 else w & 0xFFFF
    prod = ((a & 0x7FFF) * (w & 0x7FFF)) >> 15
    s = acc - prod if ((a >> 15) ^ (w >> 15)) else acc + prod
    return 32767 if s > 32767 else (-32767 if s <= -32768 else s)


def _sf16_out(acc: int) -> int:
    return (0x8000 | (-acc)) if acc < 0 else acc


def pe_dot(xs, ws, fmt=None) -> int:
    """A PE after a clear, fed (x, w) pairs in order: the cell SYS read returns."""
    if fmt is None:
        acc = 0
        for a, w in zip(xs, ws):
            acc = _sf16_step(acc, a, w)
        return _sf16_out(acc)
    acc = 0
    for a, w in zip(xs, ws):
        acc = fmt.fma(a, w, acc)
    return acc


def act_add(a: int, b: int, fmt=None) -> int:
    """ACT with f = none: the format's add."""
    return fmt.add(a, b) if fmt else q115_add(a, b)


def gemv_reference(x, W, col0: int, fmt=None) -> list:
    """The 8 outputs gemv stores for W[:, col0:col0+8]."""
    kc = len(x)
    out = []
    for j in range(N):
        rows = [pe_dot([x[k] for k in range(r, kc, N)],
                       [W[k][col0 + j] for k in range(r, kc, N)], fmt) for r in range(N)]
        y = rows[0]
        for r in range(1, N):
            y = act_add(y, rows[r], fmt)
        out.append(y)
    return out


def gemm_reference(A, W, col0: int, fmt=None) -> list:
    """The 64 outputs gemm stores for W[:, col0:col0+8], token-major."""
    kc = len(A[0])
    return [pe_dot(A[i], [W[k][col0 + j] for k in range(kc)], fmt)
            for i in range(N) for j in range(N)]
