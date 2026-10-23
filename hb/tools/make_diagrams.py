#!/usr/bin/env python3
"""The architecture diagrams in the README (docs/images/hb_*.svg), in the style
of docs/images/gpu.png: draw.io pastel blocks, monospace, white background.
  python3 hb/tools/make_diagrams.py docs/images"""
import os
import sys
from xml.sax.saxutils import escape

OUT = sys.argv[1]
FONT = "Roboto Mono, Menlo, Consolas, DejaVu Sans Mono, monospace"
C = {  # fill, stroke (draw.io palette, as gpu.png)
    "ctrl": ("#ffe6cc", "#d79b00"), "compute": ("#fff2cc", "#d6b656"), "cache": ("#d5e8d4", "#82b366"),
    "io": ("#dae8fc", "#6c8ebf"), "mem": ("#f8cecc", "#b85450"), "sw": ("#e1d5e7", "#9673a6"),
    "frame": ("#ffffff", "#000000"), "plain": ("#f5f5f5", "#666666"),
}


class SVG:
    def __init__(self, w, h):
        self.w, self.h, self.items = w, h, []

    def box(self, x, y, w, h, kind, lines, size=15, bold=False, title_bar=False):
        f, s = C[kind]
        sw = 2 if kind == "frame" else 1.5
        self.items.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{f}" stroke="{s}" stroke-width="{sw}"/>')
        if title_bar:
            self.items.append(f'<line x1="{x}" y1="{y + 34}" x2="{x + w}" y2="{y + 34}" stroke="{s}" stroke-width="{sw}"/>')
            self.text(x + w / 2, y + 23, lines[0], size + 2, True)
            return
        n = len(lines)
        lh = size * 1.35
        y0 = y + h / 2 - (n - 1) * lh / 2 + size * 0.35
        for i, t in enumerate(lines):
            self.text(x + w / 2, y0 + i * lh, t, size, bold and i == 0)

    def text(self, x, y, t, size=15, bold=False, anchor="middle", color="#000"):
        wgt = ' font-weight="bold"' if bold else ""
        self.items.append(f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}"{wgt} '
                          f'text-anchor="{anchor}" fill="{color}">{escape(t)}</text>')

    def arrow(self, x1, y1, x2, y2, both=False, color="#444", dash=False):
        d = ' stroke-dasharray="6,4"' if dash else ""
        ms = ' marker-start="url(#ah)"' if both else ""
        self.items.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="1.6"{d}'
                          f' marker-end="url(#ah)"{ms}/>')

    def save(self, name):
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
                f'viewBox="0 0 {self.w} {self.h}">'
                '<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
                'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#444"/></marker></defs>'
                f'<rect width="{self.w}" height="{self.h}" fill="#ffffff"/>')
        open(os.path.join(OUT, name), "w").write(head + "\n".join(self.items) + "</svg>\n")


def pod():
    s = SVG(1000, 760)
    s.box(20, 20, 960, 720, "frame", ["HammerBlade pod (4 x 2): bsg_manycore, 2D mesh, half-ruche X links"],
          title_bar=True)
    s.box(50, 70, 900, 56, "mem", ["DRAM model, 2 GiB (bsg_manycore test memory)"])
    xs = [50 + i * 230 for i in range(4)]
    for x in xs:
        s.box(x, 160, 210, 52, "cache", ["vcache", "4-way, 8-word lines"], size=13)
        s.arrow(x + 105, 126, x + 105, 160, both=True)
    for x in xs:
        s.box(x, 250, 210, 120, "ctrl", ["vanilla core (row 0)", "RV32IMAF", "runs the driver,", "runtime, host ops"], size=13)
        s.arrow(x + 105, 212, x + 105, 250, both=True)
    for x in xs:
        s.box(x, 410, 210, 150, "compute", ["SuperFloat tile (row 1)", "v1 core tile or", "v3 matrix tile", "SF16 / FP16 / BF16",
                                            "memory-mapped device"], size=13)
        s.arrow(x + 105, 370, x + 105, 410, both=True)
    for x in xs:
        s.box(x, 594, 210, 52, "cache", ["vcache", "4-way, 8-word lines"], size=13)
        s.arrow(x + 105, 560, x + 105, 594, both=True)
    s.box(50, 680, 900, 44, "mem", ["DRAM model (same address space)"])
    for x in xs:
        s.arrow(x + 105, 646, x + 105, 680, both=True)
    s.save("hb_pod.svg")


def v1_tile():
    s = SVG(900, 620)
    s.box(20, 20, 860, 580, "frame", ["v1 accelerator tile (hb/v/sf_hb_accel.sv)"], title_bar=True)
    s.box(50, 70, 800, 56, "io", ["bsg_manycore_endpoint_standard (mesh port)"])
    s.box(50, 160, 250, 150, "ctrl", ["CSRs", "BASE, DONE_ADDR, START", "STATUS, counters", "", "launch, DONE store"],
          size=13)
    s.box(325, 160, 250, 150, "cache", ["program memory", "512 x 16-bit,", "written by a vanilla core", "",
                                        "instruction cache", "32 entries"], size=13)
    s.box(600, 160, 250, 150, "io", ["data path", "word A = BASE + 2A", "direct: 1 load in flight", "read buffer: 8 lines",
                                     "stores: masked, posted"], size=13)
    for x in (175, 450, 725):
        s.arrow(x, 126, x, 160, both=True)
        s.arrow(x, 310, x, 350, both=True)
    s.box(50, 350, 800, 220, "compute", ["v1 core_tile (src/core_tile.sv, unchanged)"], title_bar=True)
    s.box(75, 405, 360, 145, "plain", ["8 threads, SIMT lockstep", "ALU, FMA, activation,", "LSU, 16 registers each",
                                       "fetch, decode, schedule"], size=13)
    s.box(460, 405, 365, 145, "plain", ["8 x 8 systolic array", "weight-stationary", "64 MACs per cycle",
                                        "+ 128 B scratchpad"], size=13)
    s.save("hb_v1_tile.svg")


def v3_tile():
    s = SVG(900, 780)
    s.box(20, 20, 860, 740, "frame", ["v3 matrix tile (hb/v/sf_hb_v3.sv)"], title_bar=True)
    s.box(50, 70, 800, 56, "io", ["bsg_manycore_endpoint_standard (mesh port)"])
    s.box(50, 160, 380, 110, "ctrl", ["descriptor CSRs", "A, W, C, T, K, NC", "CB_START, CB_COUNT, SHIFT",
                                      "DONE_ADDR, START"], size=13)
    s.box(470, 160, 380, 110, "io", ["DMA", "32 tags, 32 credits", "store > A load > W load"], size=13)
    s.box(50, 300, 380, 90, "cache", ["activation banks", "A loaded once, bank = k mod NA"], size=13)
    s.box(470, 300, 380, 90, "cache", ["weight slots", "4 tiles of NA x NA, streamed ahead"], size=13)
    s.box(50, 420, 800, 100, "compute", ["NA x NA weight-stationary wavefront array",
                                         "v3 PEs, NA = 8 (or 4), carry-save multiplier, 1 or 2 product stages"], size=13)
    s.box(50, 550, 800, 60, "compute", ["per-column accumulators: SF24 (Q5.19) or FP24"], size=13)
    s.box(50, 640, 380, 90, "ctrl", ["pop: one rounding to 16 bits", "SF16: shift, round, saturate"], size=13)
    s.box(470, 640, 380, 90, "io", ["store FIFOs", "C to DRAM, then DONE store"], size=13)
    s.arrow(240, 126, 240, 160)
    s.arrow(660, 126, 660, 160, both=True)
    s.arrow(660, 270, 240, 300)
    s.arrow(660, 270, 660, 300)
    s.arrow(240, 390, 240, 420)
    s.arrow(660, 390, 660, 420)
    s.arrow(450, 520, 450, 550)
    s.arrow(240, 610, 240, 640)
    s.arrow(430, 685, 470, 685)
    s.save("hb_v3_tile.svg")


def stack():
    s = SVG(1000, 640)
    s.box(20, 20, 960, 600, "frame", ["SuperFloat on HammerBlade: the stack"], title_bar=True)
    s.box(50, 70, 900, 70, "sw", ["graph compiler (specified in docs/compiler_hammerblade.md, not built)",
                                  "per-GEMM descriptors, tile assignment, DRAM layouts, SF16 exponents"], size=13)
    s.box(50, 165, 440, 120, "sw", ["host code on vanilla cores", "RISC-V GCC (upstream), Clang planned",
                                    "driver, runtime, LayerNorm,", "softmax, GELU"], size=13)
    s.box(510, 165, 440, 120, "sw", ["drivers (hb/sw)", "v1: program upload + block dispatch",
                                     "v3: descriptor writes, N split", "DONE flag polling in DMEM"], size=13)
    s.box(50, 310, 900, 60, "io", ["MMIO over the mesh: bsg_global_pod_store / load to tile CSRs"], size=13)
    s.box(50, 395, 440, 100, "compute", ["v1 core tile", "16-bit v1 kernels", "(test/gpt2/kernels.py)"], size=13)
    s.box(510, 395, 440, 100, "compute", ["v3 matrix tile", "no instruction stream:", "one descriptor per GEMM"], size=13)
    s.box(50, 520, 900, 80, "plain", ["verification and measurement: test/gpt2/prepare.py builds every launch with a bit-exact",
                                      "reference; hb/parse_run.py records cycles; hb/bench_hb.py, bench_v3.py total GPT-2"],
          size=13)
    s.arrow(270, 140, 270, 165)
    s.arrow(730, 140, 730, 165)
    s.arrow(270, 285, 270, 310)
    s.arrow(730, 285, 730, 310)
    s.arrow(270, 370, 270, 395)
    s.arrow(730, 370, 730, 395)
    s.save("hb_stack.svg")


if __name__ == "__main__":
    pod()
    v1_tile()
    v3_tile()
    stack()
