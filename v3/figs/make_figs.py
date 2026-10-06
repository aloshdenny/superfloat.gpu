#!/usr/bin/env python3
"""
Figures for the shuttle plan's section 6.9: the v2 SF16 chip's layout at
SKY130 (130 nm, the OpenFrame chip) and at GT2N (2 nm, the same RTL), each
rendered from its GDS (render_gds.py), and the two dies to scale.

  python3 make_figs.py <chip130.png> <chip2nm.png> <img130_W_um> <W130_um> <H130_um> <W2_um> <H2_um> <outdir>

img130_W_um is the width the 130 nm render spans (its GDS bounding box);
W130/H130 are the die's specified size, used for the area comparison.
"""
import math
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.image as mpimg                      # noqa: E402
import matplotlib.patches as patches                  # noqa: E402
import matplotlib.pyplot as plt                       # noqa: E402

img130, img2, IW1, W1, H1, W2, H2, out = sys.argv[1], sys.argv[2], *map(float, sys.argv[3:8]), sys.argv[8]
INK, MUTED, ACCENT, BG = "#1F3A5F", "#5B6B7F", "#D9480F", "#FFFFFF"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "text.color": INK,
                     "axes.edgecolor": MUTED, "axes.labelcolor": INK})


def scalebar(ax, width_px, um_per_px, length_um, label, img_h):
    x0, y0 = width_px * 0.06, img_h * 0.965
    ax.add_patch(patches.Rectangle((x0, y0), length_um / um_per_px, img_h * 0.012, color="white"))
    ax.text(x0, y0 - img_h * 0.012, label, color="white", fontsize=9, va="bottom", weight="bold")


# ---- the two layouts side by side, each at its own scale
a = mpimg.imread(img130)
b = mpimg.imread(img2)
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 7.4), gridspec_kw={"width_ratios": [1, 1.25]})
for ax in (ax1, ax2):
    ax.set_xticks([]); ax.set_yticks([])
ax1.imshow(a)
scalebar(ax1, a.shape[1], IW1 / a.shape[1], 1000, "1 mm", a.shape[0])
ax1.set_title(f"130 nm (SKY130): {W1 / 1e3:.2f} × {H1 / 1e3:.2f} mm = {W1 * H1 / 1e6:.2f} mm²", fontsize=10.5)
ax2.imshow(b)
scalebar(ax2, b.shape[1], W2 / b.shape[1], 50, "50 µm", b.shape[0])
ax2.set_title(f"2 nm (GT2N): {W2:.0f} × {H2:.0f} µm = {W2 * H2 / 1e6:.3f} mm²", fontsize=10.5)
fig.suptitle("The v2 SF16 chip from its GDS: four core tiles, the pin bus, dispatcher and icache",
             fontsize=11.5, weight="bold")
fig.tight_layout()
fig.savefig(f"{out}/chips_gds.png", dpi=200, facecolor=BG)
plt.close(fig)

# ---- the two dies to scale
nx, ny = math.floor(W1 / W2), math.floor(H1 / H2)
ratio = W1 * H1 / (W2 * H2)
fig, ax = plt.subplots(figsize=(7.2, 9.2))
ax.add_patch(patches.Rectangle((0, 0), W1, H1, facecolor="#EEF2F7", edgecolor=INK, linewidth=2))
for i in range(nx):
    for j in range(ny):
        ax.add_patch(patches.Rectangle((i * W2, j * H2), W2, H2, facecolor="none",
                                       edgecolor="#9AA8B8", linewidth=0.5))
ax.add_patch(patches.Rectangle((0, 0), W2, H2, facecolor=ACCENT, edgecolor=ACCENT, linewidth=1))
ax.annotate(f"one 2 nm chip\n{W2:.0f} × {H2:.0f} µm", xy=(W2, H2 / 2), xytext=(W2 * 2.6, H2 * 1.6),
            fontsize=10, color=ACCENT, weight="bold", arrowprops=dict(arrowstyle="->", color=ACCENT, lw=1.5),
            bbox=dict(boxstyle="round,pad=0.3", fc="white", ec=ACCENT, lw=1))
ax.text(W1 / 2, H1 * 0.55, f"{nx} × {ny} = {nx * ny}\n2 nm chips fit in one\n130 nm die",
        ha="center", va="center", fontsize=17, weight="bold", color=INK,
        bbox=dict(boxstyle="round,pad=0.5", fc="white", ec=INK, lw=1.2, alpha=0.92))
ax.text(W1 / 2, H1 * 0.36, f"{ratio:.0f}× less area for the same chip", ha="center", va="center",
        fontsize=12, color=INK, bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="none", alpha=0.9))
ax.set_xlim(-60, W1 + 60)
ax.set_ylim(-60, H1 + 60)
ax.set_aspect("equal")
ax.set_xlabel("µm")
ax.set_ylabel("µm")
ax.set_title(f"To scale: the 130 nm die ({W1 / 1e3:.2f} × {H1 / 1e3:.2f} mm) and the same chip at 2 nm",
             fontsize=11, weight="bold")
for s in ("top", "right"):
    ax.spines[s].set_visible(False)
fig.tight_layout()
fig.savefig(f"{out}/chips_scale.png", dpi=200, facecolor=BG)
print(f"fit {nx} x {ny} = {nx * ny}; area ratio {ratio:.1f}x")
