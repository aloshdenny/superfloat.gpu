"""
Every chip launch GPT-2 small needs, as (kernel, kc, nb) tuples.

The host splits each matrix multiply into launches that fit the chip's 64K
data window and its 31-block launch limit (kernels.py):

  decode (one token, gemv): up to 10 blocks of K = 768 per launch
    (x + 10 x 6,144 weight words); FC2's K = 3,072 runs as four K = 768
    launches whose partial sums the host adds, so all four tiles stay busy.
  prefill (8 tokens per group, gemm): up to 9 blocks of K = 768 per launch
    (A + 9 x 6,144 weight words), the same K split for FC2.
  attention: scores are K = 64 blocks of 8 positions per head, attention x V
    is K = context (rounded up to 8) with 8 blocks per head; up to 31 blocks
    per launch, heads mixed freely.

The LM head is a gemv over the 50,257-word vocabulary (6,283 blocks) for the
last token only, in prefill and in decode.
"""
D, HEADS, LAYERS, VOCAB, FFN = 768, 12, 12, 50257, 3072
N = 8
GEMV_NB, GEMM_NB, ATT_NB = 10, 9, 31


def ceil8(n: int) -> int:
    return -(-n // N) * N


def split(blocks: int, per: int):
    """Launch sizes for `blocks` blocks, at most `per` per launch."""
    out = [per] * (blocks // per)
    if blocks % per:
        out.append(blocks % per)
    return out


def matmul(kernel: str, k: int, n: int):
    """Launches of an (? x k) @ (k x n) matrix multiply, K split at 768."""
    per = GEMV_NB if kernel == "gemv" else GEMM_NB
    parts = k // D if k > D else 1
    kc = k // parts
    return [(kernel, kc, nb) for _ in range(parts) for nb in split(n // N, per)]


def attention(kernel: str, context: int):
    """Scores and attention x V for one query (gemv) or 8 queries (gemm)."""
    lp = ceil8(context)
    out = [(kernel, 64, nb) for nb in split(HEADS * lp // N, ATT_NB)]
    out += [(kernel, lp, nb) for nb in split(HEADS * (64 // N), ATT_NB)]
    return out


def layer(kernel: str, context: int):
    return (matmul(kernel, D, 3 * D) + attention(kernel, context) + matmul(kernel, D, D)
            + matmul(kernel, D, FFN) + matmul(kernel, FFN, D))


def lm_head():
    return [("gemv", D, nb) for nb in split(ceil8(VOCAB) // N, GEMV_NB)]


def decode_step(context: int):
    """One generated token with `context` positions in the KV cache (itself included)."""
    return [l for _ in range(LAYERS) for l in layer("gemv", context)] + lm_head()


def prefill(prompt: int):
    """The prompt in groups of 8 tokens (gemm), causal context per group, then
    the LM head for the last token. A short last group costs a full one."""
    out = []
    for g in range(-(-prompt // N)):
        ctx = min(prompt, N * (g + 1))
        out += [l for _ in range(LAYERS) for l in layer("gemm", ctx)]
    return out + lm_head()


def weight_words():
    """Weights streamed per decode token (matrix multiplies only)."""
    return LAYERS * (D * 3 * D + D * D + D * FFN + FFN * D) + D * VOCAB
