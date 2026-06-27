#!/usr/bin/env python3
"""
KLayout Physical Layout Generator for ATREIDES GPU
Generates high-quality physical layout images from Sky130 PDK GDS files.

Usage:
  /Applications/KLayout/klayout.app/Contents/MacOS/klayout -b -r scripts/generate_layout.py
  Or: make layout
"""

import klayout.db as db
import klayout.lay as lay
import os
import math

# ── Configuration ─────────────────────────────────────────────────────────────

GDS_FILE   = "/Users/aoxo/vscode/superfloat.gpu/librelane/systolic_array/runs/RUN_2026-06-24_19-18-33/final/gds/systolic_array.gds"
OUTPUT_DIR = "/Users/aoxo/vscode/superfloat.gpu/"
os.makedirs(OUTPUT_DIR, exist_ok=True)

TT_TILE_W = 160.0   # µm — one Tiny Tapeout tile
TT_TILE_H = 100.0   # µm

# ── Load GDS ──────────────────────────────────────────────────────────────────

print("=" * 70)
print("  ATREIDES GPU — Physical Layout Generator  |  Sky130 PDK (SkyWater 130nm)")
print("=" * 70)
print(f"\nLoading: {GDS_FILE}")

layout = db.Layout()
layout.read(GDS_FILE)
dbu = layout.dbu

# Find largest top cell by bounding-box area
top_cell, max_area = None, 0
for i in range(layout.cells()):
    cell = layout.cell(i)
    bbox = cell.bbox()
    if not bbox.empty():
        area = bbox.width() * bbox.height()
        if area > max_area:
            max_area = area
            top_cell = cell

die_w = top_cell.bbox().width() * dbu
die_h = top_cell.bbox().height() * dbu

# Tiny Tapeout tile estimate
tt_tiles_x     = math.ceil(die_w / TT_TILE_W)
tt_tiles_y     = math.ceil(die_h / TT_TILE_H)
tt_total_tiles = tt_tiles_x * tt_tiles_y
tt_utilization = (die_w * die_h) / (tt_total_tiles * TT_TILE_W * TT_TILE_H) * 100

# Shape count
total_shapes = sum(
    layout.cell(i).shapes(li).size()
    for li in layout.layer_indices()
    for i in range(layout.cells())
)

print(f"\n  Design  : {top_cell.name}")
print(f"  Die     : {die_w:.0f} × {die_h:.0f} µm  ({die_w/1000:.2f} × {die_h/1000:.2f} mm)")
print(f"  Cells   : {layout.cells()}")
print(f"  Shapes  : {total_shapes:,}")
print(f"  Layers  : {layout.layers()}")
print(f"  TT tiles: {tt_total_tiles} ({tt_tiles_x}×{tt_tiles_y})  —  utilisation {tt_utilization:.1f}%")

# ── Layer colours ─────────────────────────────────────────────────────────────
# Visible layers: li (cyan), met1/met3 (yellow), met2/met4/poly (pink),
#                 diff/tap (amber).  Everything else is hidden.

SKY130_COLORS = {
    # (layer, datatype): (color_hex, visible, fill)
    (68, 20): (0x00D4FF, True,  True),   # li.drawing   — cyan
    (68, 44): (0x00D4FF, False, False),
    (68,  5): (0x00BFFF, False, False),
    (68, 16): (0x00CED1, False, False),

    (69, 20): (0xFFD93D, True,  True),   # met1.drawing — gold
    (69, 44): (0xFFD700, False, False),
    (69,  5): (0xFFCC00, False, False),
    (69, 16): (0xFFAA00, False, False),

    (70, 20): (0xFF69B4, True,  True),   # met2.drawing — pink
    (70, 44): (0xFF6B81, False, False),
    (70,  5): (0xFF1493, False, False),
    (70, 16): (0xDB7093, False, False),

    (71, 20): (0xFFE066, True,  True),   # met3.drawing — light gold
    (71, 44): (0xFFD700, False, False),
    (71,  5): (0xFFCC00, False, False),
    (71, 16): (0xFFAA00, False, False),

    (72, 20): (0xFF69B4, True,  True),   # met4.drawing — pink
    (72,  5): (0xFF1493, False, False),
    (72, 16): (0xDB7093, False, False),

    (67, 20): (0xFF6B81, True,  True),   # poly.drawing — pink
    (67, 44): (0xFF69B4, False, False),
    (67,  5): (0xFF1493, False, False),
    (67, 16): (0xDB7093, False, False),

    (65, 20): (0xFFD93D, True,  True),   # diff.drawing — gold
    (65, 44): (0xFFCC00, False, False),

    (66, 20): (0xFFCC00, True,  True),   # tap.drawing  — amber
    (66, 44): (0x00D4FF, False, False),

    # Wells, implants, vias, area markers — all hidden
    (64,  20): (0x444444, False, False),
    (64,  16): (0x444444, False, False),
    (64,   5): (0x444444, False, False),
    (64,  59): (0x444444, False, False),
    (122, 16): (0x333333, False, False),
    (93,  44): (0x00CED1, False, False),
    (94,  20): (0xFF69B4, False, False),
    (78,  44): (0x00D4FF, False, False),
    (81,   4): (0x222222, False, False),
    (81,  14): (0x333333, False, False),
    (81,  23): (0x222222, False, False),
    (83,  44): (0x444444, False, False),
    (235,  4): (0x333333, False, False),
    (236,  0): (0x555555, False, False),

    (95, 20): (0xFF6600, True,  True),   # capacitor — orange
}

# ── Layout view ───────────────────────────────────────────────────────────────

lv = lay.LayoutView()
lv.set_config("background-color", "#000000")
lv.set_config("grid-visible",     "false")
lv.set_config("text-visible",     "false")

cell_view_index = lv.load_layout(GDS_FILE, True)
cv = lv.cellview(cell_view_index)
cv.cell = top_cell
lv.max_hier_levels = 100

layer_iter = lv.begin_layers()
idx = 0
while not layer_iter.at_end():
    lp     = layer_iter.current()
    source = str(lp.source)
    layer_key = None
    try:
        if '/' in source and '@' in source:
            parts     = source.split('@')[0].split('/')
            layer_key = (int(parts[0]), int(parts[1]))
    except Exception:
        pass

    if layer_key and layer_key in SKY130_COLORS:
        color, visible, is_fill = SKY130_COLORS[layer_key]
        lp.fill_brightness = 0 if is_fill else -20
    else:
        color   = [0xFFD93D, 0xFF69B4, 0x00D4FF][idx % 3]
        visible = True
        lp.fill_brightness = 0

    lp.fill_color      = color
    lp.frame_color     = color
    lp.visible         = visible
    lp.frame_brightness = 10
    lp.transparent     = False
    lp.width           = 1
    lp.dither_pattern  = 0

    lv.set_layer_properties(layer_iter, lp)
    idx += 1
    layer_iter.next()

# ── Export images ─────────────────────────────────────────────────────────────

lv.zoom_fit()
box = lv.box()
cx, cy = box.center().x, box.center().y

def zoom_export(filename, zoom_factor, w, h, box_override=None):
    if box_override:
        lv.zoom_box(box_override)
    else:
        half = box.width() / zoom_factor / 2
        lv.zoom_box(db.DBox(cx - half, cy - half, cx + half, cy + half))
    path = os.path.join(OUTPUT_DIR, filename)
    lv.save_image(path, w, h)
    return path

print("\nGenerating layout images...")

margin = box.width() * 0.02
outputs = [
    ("Full die (4K)",        zoom_export("gpu_layout_full.png",   1,   4096, 4096,
                                         db.DBox(box.left - margin, box.bottom - margin,
                                                 box.right + margin, box.top + margin))),
    ("10× — module level",   zoom_export("gpu_layout_10x.png",    10,  2048, 2048)),
    ("50× — cell blocks",    zoom_export("gpu_layout_50x.png",    50,  2048, 2048)),
    ("100× — gate level",    zoom_export("gpu_layout_100x.png",   100, 2048, 2048)),
    ("500× — transistors",   zoom_export("gpu_layout_500x.png",   500, 2048, 2048)),
    ("Corner view (I/O)",    zoom_export("gpu_layout_corner.png", 1,   2048, 2048,
                                         db.DBox(box.right - box.width()/5,
                                                 box.top   - box.width()/5,
                                                 box.right, box.top))),
]

for label, path in outputs:
    size_kb = os.path.getsize(path) // 1024
    print(f"  ✓  {os.path.basename(path):35} {label} ({size_kb} KB)")

# ── Summary ───────────────────────────────────────────────────────────────────

print(f"""
{"=" * 70}
  ATREIDES GPU — Layout Generation Complete
{"=" * 70}

  Chip    : {top_cell.name}
  Size    : {die_w:.0f} × {die_h:.0f} µm  ({die_w/1000:.2f} × {die_h/1000:.2f} mm)
  PDK     : SkyWater 130nm
  Cells   : {layout.cells()}
  Shapes  : {total_shapes:,}
  Layers  : {layout.layers()}

  Tiny Tapeout
    Tile  : {TT_TILE_W:.0f} × {TT_TILE_H:.0f} µm
    Grid  : {tt_tiles_x} × {tt_tiles_y}
    Total : {tt_total_tiles} tiles  ({tt_utilization:.1f}% area utilisation)

  Output  : {OUTPUT_DIR}
{"=" * 70}
""")