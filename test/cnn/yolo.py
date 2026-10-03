"""
YOLOv8n (Ultralytics, scale n: depth 0.33, width 0.25) at 640 x 640, in numpy,
split the way the OpenFrame chip runs it (docs/cnn_benchmark.md):

  chip: every convolution, as a GEMM over im2col patches (K = Cin * k * k)
  host: im2col, bias, SiLU, residual adds, max-pool, upsample, concat and the
        detection head's decode (DFL softmax, boxes, class scores)

Batch norm is folded into each convolution's weights and bias. The weights
are synthetic (seeded, He-scaled) and the input is a synthetic image: the
benchmark measures latency and energy, not detection quality, and the chip's
cycle counts do not depend on the values.

  Model().forward(image) -> outputs; .convs lists every convolution in order
  with its shape, and .host_s the host's time per operation kind.
"""
import time

import numpy as np

IMG = 640
NC = 80                 # COCO classes
REG_MAX = 16            # DFL bins


class Conv:
    """A convolution's GEMM shape: (Cout x K) @ (K x Hout*Wout)."""

    def __init__(self, name, cin, cout, k, s, hin, act=True):
        self.name, self.cin, self.cout, self.k, self.s, self.act = name, cin, cout, k, s, act
        self.hin = hin
        self.hout = (hin + 2 * (k // 2) - k) // s + 1
        self.K = cin * k * k
        self.N = self.hout * self.hout

    @property
    def macs(self):
        return self.cout * self.K * self.N


def im2col(x, k, s):
    """x (C, H, W) -> patches (C*k*k, Hout*Wout), zero padding k//2."""
    c, h, w = x.shape
    p = k // 2
    xp = np.pad(x, ((0, 0), (p, p), (p, p))) if p else x
    ho = (h + 2 * p - k) // s + 1
    cols = np.empty((c, k, k, ho, ho), dtype=x.dtype)
    for i in range(k):
        for j in range(k):
            cols[:, i, j] = xp[:, i:i + s * ho:s, j:j + s * ho:s]
    return cols.reshape(c * k * k, ho * ho)


def silu(x):
    return x / (1.0 + np.exp(-x))


class Model:
    def __init__(self, seed=0, keep=()):
        self.rng = np.random.default_rng(seed)
        self.convs = []
        self.params = {}
        self.keep = set(keep)             # conv names whose (W, patches) to keep
        self.kept = {}
        self.host_s = {}

    # -- timing -----------------------------------------------------------
    def _host(self, kind, f, *a):
        t = time.perf_counter()
        r = f(*a)
        self.host_s[kind] = self.host_s.get(kind, 0.0) + time.perf_counter() - t
        return r

    # -- layers -----------------------------------------------------------
    def conv(self, name, x, cout, k=1, s=1, act=True):
        cin, h, _ = x.shape
        c = Conv(name, cin, cout, k, s, h, act)
        self.convs.append(c)
        if name not in self.params:
            std = np.sqrt(2.0 / c.K)
            self.params[name] = (self.rng.normal(0.0, std, (cout, c.K)).astype(np.float32),
                                 self.rng.normal(0.0, 0.05, cout).astype(np.float32))
        W, b = self.params[name]
        P = self._host("im2col", im2col, x, k, s)
        if name in self.keep:
            self.kept[name] = (W, P)
        y = W @ P                                                       # chip
        y = self._host("bias", lambda y: y + b[:, None], y)
        if act:
            y = self._host("silu", silu, y)
        return y.reshape(cout, c.hout, c.hout)

    def bottleneck(self, name, x, c, shortcut):
        y = self.conv(name + ".cv1", x, c, 3)
        y = self.conv(name + ".cv2", y, c, 3)
        return self._host("add", np.add, x, y) if shortcut else y

    def c2f(self, name, x, cout, n, shortcut):
        c = cout // 2
        y = self.conv(name + ".cv1", x, 2 * c)
        ys = [y[:c], y[c:]]
        for i in range(n):
            ys.append(self.bottleneck(f"{name}.m{i}", ys[-1], c, shortcut))
        return self.conv(name + ".cv2", self._host("concat", np.concatenate, ys), cout)

    def sppf(self, name, x, cout):
        c = x.shape[0] // 2
        y = self.conv(name + ".cv1", x, c)
        ys = [y]
        for _ in range(3):
            ys.append(self._host("maxpool", maxpool5, ys[-1]))
        return self.conv(name + ".cv2", self._host("concat", np.concatenate, ys), cout)

    def detect(self, feats):
        c2 = max(16, feats[0].shape[0] // 4, REG_MAX * 4)
        c3 = max(feats[0].shape[0], min(NC, 100))
        outs = []
        for i, x in enumerate(feats):
            b = self.conv(f"22.cv2.{i}.0", x, c2, 3)
            b = self.conv(f"22.cv2.{i}.1", b, c2, 3)
            b = self.conv(f"22.cv2.{i}.2", b, 4 * REG_MAX, 1, act=False)
            c = self.conv(f"22.cv3.{i}.0", x, c3, 3)
            c = self.conv(f"22.cv3.{i}.1", c, c3, 3)
            c = self.conv(f"22.cv3.{i}.2", c, NC, 1, act=False)
            outs.append(self._host("decode", decode, b, c, 8 * 2 ** i))
        return np.concatenate(outs, axis=1)

    # -- network ------------------------------------------------------------
    def forward(self, img):
        self.convs, self.host_s = [], {}
        up = lambda t: self._host("upsample", upsample2, t)                     # noqa: E731
        cat = lambda *t: self._host("concat", np.concatenate, t)                # noqa: E731
        x = self.conv("0", img, 16, 3, 2)
        x = self.conv("1", x, 32, 3, 2)
        x = self.c2f("2", x, 32, 1, True)
        x = self.conv("3", x, 64, 3, 2)
        p3 = self.c2f("4", x, 64, 2, True)
        x = self.conv("5", p3, 128, 3, 2)
        p4 = self.c2f("6", x, 128, 2, True)
        x = self.conv("7", p4, 256, 3, 2)
        x = self.c2f("8", x, 256, 1, True)
        p5 = self.sppf("9", x, 256)
        h12 = self.c2f("12", cat(up(p5), p4), 128, 1, False)
        n3 = self.c2f("15", cat(up(h12), p3), 64, 1, False)
        h18 = self.c2f("18", cat(self.conv("16", n3, 64, 3, 2), h12), 128, 1, False)
        n5 = self.c2f("21", cat(self.conv("19", h18, 128, 3, 2), p5), 256, 1, False)
        return self.detect([n3, h18, n5])


def maxpool5(x):
    """5x5 max-pool, stride 1, padding 2."""
    xp = np.pad(x, ((0, 0), (2, 2), (2, 2)), constant_values=-np.inf)
    h = x.shape[1]
    out = xp[:, 0:h, 0:h].copy()
    for i in range(5):
        for j in range(5):
            np.maximum(out, xp[:, i:i + h, j:j + h], out=out)
    return out


def upsample2(x):
    return x.repeat(2, axis=1).repeat(2, axis=2)


def decode(box, cls, stride):
    """DFL expectation over 16 bins per side, anchor-relative boxes, sigmoid scores."""
    h = box.shape[1]
    d = box.reshape(4, REG_MAX, h * h)
    d = np.exp(d - d.max(axis=1, keepdims=True))
    d = (d / d.sum(axis=1, keepdims=True) * np.arange(REG_MAX)[None, :, None]).sum(axis=1)
    ys, xs = np.mgrid[0:h, 0:h]
    ax, ay = xs.ravel() + 0.5, ys.ravel() + 0.5
    xyxy = np.stack([ax - d[0], ay - d[1], ax + d[2], ay + d[3]]) * stride
    return np.concatenate([xyxy, 1.0 / (1.0 + np.exp(-cls.reshape(NC, h * h)))])


def image(seed=1):
    """A smooth synthetic RGB image in [0, 1], 640 x 640."""
    rng = np.random.default_rng(seed)
    low = rng.random((3, IMG // 32, IMG // 32)).astype(np.float32)
    img = low.repeat(32, axis=1).repeat(32, axis=2)
    return np.clip(img + 0.1 * rng.standard_normal(img.shape).astype(np.float32), 0, 1)


if __name__ == "__main__":
    m = Model()
    t = time.perf_counter()
    out = m.forward(image())
    total = time.perf_counter() - t
    macs = sum(c.macs for c in m.convs)
    print(f"{len(m.convs)} convolutions, {macs / 1e9:.3f} GMACs ({2 * macs / 1e9:.2f} GFLOPs), "
          f"{sum(c.cout * c.K for c in m.convs) / 1e6:.3f} M weights; output {out.shape}")
    print(f"numpy forward {total:.2f} s; host ops " +
          ", ".join(f"{k} {v * 1e3:.1f} ms" for k, v in sorted(m.host_s.items())))
