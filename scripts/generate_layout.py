#!/usr/bin/env python3
"""
KLayout Physical Layout Generator for ATREIDES GPU
Generates high-quality physical layout images from Sky130 PDK GDS files.

Usage:
  /Applications/KLayout/klayout.app/Contents/MacOS/klayout -b -r scripts/generate_layout.py
  
  Or via Makefile:
  make layout
"""

import klayout.db as db
import klayout.lay as lay
import os

# Configuration
GDS_FILE = "gds/atreides.gds"
OUTPUT_DIR = "build"

os.makedirs(OUTPUT_DIR, exist_ok=True)

print("="*70)
print("  ATREIDES GPU - Physical Layout Generator")
print("  Sky130 PDK (SkyWater 130nm)")
print("="*70)

print(f"\nLoading: {GDS_FILE}")

# Load layout
layout = db.Layout()
layout.read(GDS_FILE)
dbu = layout.dbu

# Find top cell
top_cell = None
max_area = 0
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

# Count shapes
total_shapes = 0
for li in layout.layer_indices():
    for i in range(layout.cells()):
        total_shapes += layout.cell(i).shapes(li).size()

print(f"\n{'─'*50}")
print(f"  Design: {top_cell.name}")
print(f"  Die Size: {die_w:.0f} × {die_h:.0f} µm ({die_w/1000:.2f} × {die_h/1000:.2f} mm)")
print(f"  Process: SkyWater 130nm")
print(f"  Cells: {layout.cells()}")
print(f"  Shapes: {total_shapes:,}")
print(f"  Layers: {layout.layers()}")
print(f"{'─'*50}")

# Create layout view
lv = lay.LayoutView()
lv.set_config("background-color", "#0f0f23")  # Deep navy background
lv.set_config("grid-visible", "false")
lv.set_config("text-visible", "true")

cell_view_index = lv.load_layout(GDS_FILE, True)
cv = lv.cellview(cell_view_index)
cv.cell = top_cell
lv.max_hier_levels = 100

# Vibrant color palette for semiconductor layers
LAYER_COLORS = [
    0x00D4FF,  # Cyan - Local Interconnect
    0xFF6B6B,  # Coral - Metal layers
    0x2ED573,  # Emerald - Poly
    0xFFD93D,  # Gold - Active
    0xA55EEA,  # Purple - Via
    0x1DD1A1,  # Mint - N-well
    0xFF9F43,  # Orange - P-well
    0x54A0FF,  # Blue - Metal1
    0xFFC048,  # Amber - Metal2
    0xFF6B81,  # Pink - Metal3
    0x5F27CD,  # Indigo - Via2
    0x20BF6B,  # Lime - Diffusion
    0xEB3B5A,  # Red - Contact
    0x8854D0,  # Violet - Via3
    0xFA8231,  # Dark Orange - Metal4
    0x3867D6,  # Navy - Metal5
    0xF7B731,  # Amber - Highlight
    0x26DE81,  # Mint Green
    0xFC5C65,  # Salmon
    0x45AAF2,  # Sky Blue
]

# Apply colors
layer_iter = lv.begin_layers()
idx = 0
while not layer_iter.at_end():
    lp = layer_iter.current()
    color = LAYER_COLORS[idx % len(LAYER_COLORS)]
    
    lp.fill_color = color
    lp.frame_color = color
    lp.fill_brightness = 10
    lp.frame_brightness = 20
    lp.visible = True
    lp.transparent = False
    lp.width = 1
    lp.dither_pattern = 0
    
    lv.set_layer_properties(layer_iter, lp)
    idx += 1
    layer_iter.next()

# Zoom to fit
lv.zoom_fit()
box = lv.box()
center_x, center_y = box.center().x, box.center().y

# Generate images at different scales
print("\nGenerating layout images...")

outputs = []

# 1. Full die (4K)
lv.zoom_fit()
margin = box.width() * 0.02
lv.zoom_box(db.DBox(box.left - margin, box.bottom - margin,
                     box.right + margin, box.top + margin))
path = os.path.join(OUTPUT_DIR, "gpu_layout_full.png")
lv.save_image(path, 4096, 4096)
outputs.append(("Full Die (4K)", path))
print(f"  ✓ Full die view")

# 2. 10x zoom - Module level
zoom = 10
half = box.width() / zoom / 2
lv.zoom_box(db.DBox(center_x - half, center_y - half, center_x + half, center_y + half))
path = os.path.join(OUTPUT_DIR, "gpu_layout_10x.png")
lv.save_image(path, 2048, 2048)
outputs.append(("10x Zoom (Modules)", path))
print(f"  ✓ 10x zoom - module level")

# 3. 50x zoom - Standard cell blocks
zoom = 50
half = box.width() / zoom / 2
lv.zoom_box(db.DBox(center_x - half, center_y - half, center_x + half, center_y + half))
path = os.path.join(OUTPUT_DIR, "gpu_layout_50x.png")
lv.save_image(path, 2048, 2048)
outputs.append(("50x Zoom (Cells)", path))
print(f"  ✓ 50x zoom - cell blocks")

# 4. 100x zoom - Individual cells
zoom = 100
half = box.width() / zoom / 2
lv.zoom_box(db.DBox(center_x - half, center_y - half, center_x + half, center_y + half))
path = os.path.join(OUTPUT_DIR, "gpu_layout_100x.png")
lv.save_image(path, 2048, 2048)
outputs.append(("100x Zoom (Gates)", path))
print(f"  ✓ 100x zoom - gate level")

# 5. 500x zoom - Transistor level
zoom = 500
half = box.width() / zoom / 2
lv.zoom_box(db.DBox(center_x - half, center_y - half, center_x + half, center_y + half))
path = os.path.join(OUTPUT_DIR, "gpu_layout_500x.png")
lv.save_image(path, 2048, 2048)
outputs.append(("500x Zoom (Transistors)", path))
print(f"  ✓ 500x zoom - transistor level")

# 6. Corner view (I/O pads & memory)
corner_size = box.width() / 5
lv.zoom_box(db.DBox(box.right - corner_size, box.top - corner_size, box.right, box.top))
path = os.path.join(OUTPUT_DIR, "gpu_layout_corner.png")
lv.save_image(path, 2048, 2048)
outputs.append(("Corner View (I/O)", path))
print(f"  ✓ Corner view")

# Summary
print("\n" + "="*70)
print("  ✓ Physical Layout Generation Complete!")
print("="*70)
print(f"\n  Output: {OUTPUT_DIR}/")
print("\n  Generated files:")
for name, path in outputs:
    size = os.path.getsize(path)
    print(f"    • {os.path.basename(path):30} {name} ({size//1024}KB)")

print(f"""
  Design Summary:
  ┌──────────────────────────────────────┐
  │  Chip: {top_cell.name:28} │
  │  Size: {die_w:.0f} × {die_h:.0f} µm{' '*(20-len(f'{die_w:.0f} × {die_h:.0f}'))}│
  │  PDK:  SkyWater 130nm              │
  │  Shapes: {total_shapes:,}{' '*(24-len(f'{total_shapes:,}'))}│
  └──────────────────────────────────────┘
""")
print("="*70)
