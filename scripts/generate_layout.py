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
GDS_FILE = "gds/atreides_v2.gds"
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
lv.set_config("background-color", "#000000")  # Pure black background (matches reference)
lv.set_config("grid-visible", "false")
lv.set_config("text-visible", "false")  # Hide text for cleaner look

cell_view_index = lv.load_layout(GDS_FILE, True)
cv = lv.cellview(cell_view_index)
cv.cell = top_cell
lv.max_hier_levels = 100

# Sky130 layer colors matching reference image (Yellow, Pink, Cyan on black)
# Based on actual GDS layer analysis:
#   68/20 (li.drawing): 1.2M shapes - Local Interconnect - CYAN (power grid)
#   69/20 (met1.drawing): 587K shapes - Metal 1 - YELLOW/GOLD
#   70/20 (met2.drawing): 81K shapes - Metal 2 - PINK
#   67/20 (poly.drawing): 269K shapes - Polysilicon - PINK
#   65/20 (diff.drawing): Active - YELLOW
#   71/20 (met3.drawing): Metal 3 - YELLOW
#   72/20 (met4.drawing): Metal 4 - PINK

SKY130_COLORS = {
    # Layer/Datatype : (color, visible, is_fill_layer)
    # Local Interconnect - Cyan (power rails)
    (68, 20): (0x00D4FF, True, True),    # li.drawing - Cyan
    (68, 44): (0x00D4FF, False, False),  # li.label - hidden
    (68, 5):  (0x00BFFF, False, False),  # li.res - hidden
    (68, 16): (0x00CED1, False, False),  # li.cut - hidden
    
    # Metal 1 - Yellow/Gold
    (69, 20): (0xFFD93D, True, True),    # met1.drawing - Yellow Gold
    (69, 44): (0xFFD700, False, False),  # met1.label - hidden
    (69, 5):  (0xFFCC00, False, False),  # met1.res - hidden
    (69, 16): (0xFFAA00, False, False),  # met1.cut - hidden
    
    # Metal 2 - Pink
    (70, 20): (0xFF69B4, True, True),    # met2.drawing - Hot Pink
    (70, 44): (0xFF6B81, False, False),  # met2.label - hidden
    (70, 5):  (0xFF1493, False, False),  # met2.res - hidden
    (70, 16): (0xDB7093, False, False),  # met2.cut - hidden
    
    # Metal 3 - Yellow
    (71, 20): (0xFFE066, True, True),    # met3.drawing - Light Gold
    (71, 44): (0xFFD700, False, False),  # met3.label - hidden
    (71, 5):  (0xFFCC00, False, False),  # met3.res - hidden
    (71, 16): (0xFFAA00, False, False),  # met3.cut - hidden
    
    # Metal 4 - Pink
    (72, 20): (0xFF69B4, True, True),    # met4.drawing - Hot Pink
    (72, 5):  (0xFF1493, False, False),  # met4.res - hidden
    (72, 16): (0xDB7093, False, False),  # met4.cut - hidden
    
    # Polysilicon - Pink/Magenta
    (67, 20): (0xFF6B81, True, True),    # poly.drawing - Pink
    (67, 44): (0xFF69B4, False, False),  # poly.label/mcon - hidden
    (67, 5):  (0xFF1493, False, False),  # poly.res - hidden
    (67, 16): (0xDB7093, False, False),  # poly.cut - hidden
    
    # Active/Diffusion - Yellow
    (65, 20): (0xFFD93D, True, True),    # diff.drawing - Yellow Gold
    (65, 44): (0xFFCC00, False, False),  # diff.label - hidden
    
    # Tap - Yellow
    (66, 20): (0xFFCC00, True, True),    # tap.drawing - Amber
    (66, 44): (0x00D4FF, False, False),  # tap.label/licon - hidden
    
    # Wells - Hide for cleaner look
    (64, 20): (0x444444, False, False),  # nwell.drawing - hidden
    (64, 16): (0x444444, False, False),  # nwell.pin - hidden
    (64, 5):  (0x444444, False, False),  # nwell.label - hidden
    (64, 59): (0x444444, False, False),  # pwell.pin - hidden
    (122, 16): (0x333333, False, False), # pwell.drawing - hidden
    
    # Implants - Hide
    (93, 44): (0x00CED1, False, False),  # nsdm - hidden
    (94, 20): (0xFF69B4, False, False),  # psdm - hidden
    
    # Vias - Small cyan dots
    (78, 44): (0x00D4FF, False, False),  # via - hidden
    
    # Capacitor
    (95, 20): (0xFF6600, True, True),    # capacitor - Orange
    
    # Area IDs and boundaries - Hide
    (81, 4):  (0x222222, False, False),  # areaid.sc - hidden
    (81, 14): (0x333333, False, False),  # areaid.frame - hidden
    (81, 23): (0x222222, False, False),  # areaid.seal - hidden
    (83, 44): (0x444444, False, False),  # boundary - hidden
    (235, 4): (0x333333, False, False),  # prBoundary - hidden
    (236, 0): (0x555555, False, False),  # padframe - hidden
}

# Apply Sky130-specific colors
layer_iter = lv.begin_layers()
idx = 0
while not layer_iter.at_end():
    lp = layer_iter.current()
    
    # Parse layer info from source
    source = str(lp.source)
    layer_key = None
    try:
        if '/' in source and '@' in source:
            parts = source.split('@')[0].split('/')
            layer_num = int(parts[0])
            datatype = int(parts[1])
            layer_key = (layer_num, datatype)
    except:
        pass
    
    # Apply color based on layer mapping
    if layer_key and layer_key in SKY130_COLORS:
        color, visible, is_fill = SKY130_COLORS[layer_key]
        lp.fill_color = color
        lp.frame_color = color
        lp.visible = visible
        lp.fill_brightness = 0 if is_fill else -20
        lp.frame_brightness = 10
        lp.transparent = False
        lp.width = 1
        lp.dither_pattern = 0
    else:
        # Default: cycle through yellow, pink, cyan
        cycle_colors = [0xFFD93D, 0xFF69B4, 0x00D4FF]
        color = cycle_colors[idx % 3]
        lp.fill_color = color
        lp.frame_color = color
        lp.visible = True
        lp.fill_brightness = 0
        lp.frame_brightness = 10
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
