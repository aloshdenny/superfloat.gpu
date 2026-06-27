#!/usr/bin/env python3
"""
KLayout Zoom Sequence Generator for ATREIDES GPU
Generates a series of high-resolution images for zoom-out video creation.

Usage:
  /Applications/KLayout/klayout.app/Contents/MacOS/klayout -b -r scripts/generate_zoom_sequence.py

Then create video with ffmpeg:
  ffmpeg -framerate 30 -i build/zoom_sequence/frame_%04d.png -c:v libx264 -pix_fmt yuv420p -crf 18 build/gpu_zoomout.mp4
"""

import klayout.db as db
import klayout.lay as lay
import os
import math

# =============================================================================
# Configuration
# =============================================================================

GDS_FILE = "gds/atreides.gds"
LYP_FILE = "scripts/sky130.lyp"
OUTPUT_DIR = "build/zoom_sequence"

# Image resolution (4K for high quality video)
IMAGE_WIDTH = 3840
IMAGE_HEIGHT = 2160

# Number of frames to generate (more = smoother video)
NUM_FRAMES = 600

# Zoom range (in terms of view width in micrometers)
# Start zoomed in at transistor level, end at full chip
MIN_VIEW_SIZE = 5.0      # 5 µm - transistor level
MAX_VIEW_SIZE = 2500.0   # 2500 µm - full chip + margin

# Use exponential zoom for smooth visual progression
USE_EXPONENTIAL_ZOOM = True

# =============================================================================
# Setup
# =============================================================================

os.makedirs(OUTPUT_DIR, exist_ok=True)

print("="*70)
print("  ATREIDES GPU - Zoom Sequence Generator")
print("  For creating chip zoom-out videos")
print("="*70)

print(f"\nConfiguration:")
print(f"  Resolution: {IMAGE_WIDTH} x {IMAGE_HEIGHT}")
print(f"  Frames: {NUM_FRAMES}")
print(f"  Zoom range: {MIN_VIEW_SIZE} µm → {MAX_VIEW_SIZE} µm")
print(f"  Output: {OUTPUT_DIR}/")

# Load layout
print(f"\nLoading GDS: {GDS_FILE}")
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

die_bbox = top_cell.bbox()
die_width = die_bbox.width() * dbu
die_height = die_bbox.height() * dbu

print(f"  Top cell: {top_cell.name}")
print(f"  Die size: {die_width:.0f} x {die_height:.0f} µm")

# =============================================================================
# Create Layout View with Layer Properties
# =============================================================================

print(f"\nSetting up view with layer properties...")
lv = lay.LayoutView()

# Dark background for cinematic look
lv.set_config("background-color", "#0a0a12")
lv.set_config("grid-visible", "false")
lv.set_config("text-visible", "true")

# Load layout
cell_view_index = lv.load_layout(GDS_FILE, True)
cv = lv.cellview(cell_view_index)
cv.cell = top_cell
lv.max_hier_levels = 100

# Load layer properties file if it exists
if os.path.exists(LYP_FILE):
    print(f"  Loading layer properties: {LYP_FILE}")
    lv.load_layer_props(LYP_FILE)
else:
    print(f"  Layer properties file not found, using default colors")
    # Apply vibrant default colors
    COLORS = [
        0xFF8C00,  # Orange - N-well
        0x22DD22,  # Green - Diffusion
        0xFF0000,  # Red - Poly
        0x00FFFF,  # Cyan - LI
        0x4444FF,  # Blue - Metal1
        0xFF00FF,  # Magenta - Metal2
        0x00FF00,  # Lime - Metal3
        0xFFFF00,  # Yellow - Metal4
        0xFF8844,  # Orange - Contacts
        0x8844FF,  # Purple - Vias
    ]
    layer_iter = lv.begin_layers()
    idx = 0
    while not layer_iter.at_end():
        lp = layer_iter.current()
        color = COLORS[idx % len(COLORS)]
        lp.fill_color = color
        lp.frame_color = color
        lp.fill_brightness = 0
        lp.frame_brightness = 10
        lp.visible = True
        lp.transparent = False
        lp.width = 1
        lp.dither_pattern = 0
        lv.set_layer_properties(layer_iter, lp)
        idx += 1
        layer_iter.next()

# =============================================================================
# Find an interesting center point (center of active circuitry)
# =============================================================================

# Use the center of the die
center_x = (die_bbox.left + die_bbox.right) / 2 * dbu
center_y = (die_bbox.bottom + die_bbox.top) / 2 * dbu

print(f"  Zoom center: ({center_x:.1f}, {center_y:.1f}) µm")

# =============================================================================
# Generate Zoom Sequence
# =============================================================================

print(f"\nGenerating {NUM_FRAMES} frames...")
print("─" * 50)

for frame in range(NUM_FRAMES):
    # Calculate progress (0 to 1)
    t = frame / (NUM_FRAMES - 1)
    
    if USE_EXPONENTIAL_ZOOM:
        # Exponential interpolation for smooth visual zoom
        # This makes the zoom feel constant in terms of visual change
        log_min = math.log(MIN_VIEW_SIZE)
        log_max = math.log(MAX_VIEW_SIZE)
        view_size = math.exp(log_min + t * (log_max - log_min))
    else:
        # Linear interpolation
        view_size = MIN_VIEW_SIZE + t * (MAX_VIEW_SIZE - MIN_VIEW_SIZE)
    
    # Calculate view box (maintain aspect ratio)
    aspect = IMAGE_WIDTH / IMAGE_HEIGHT
    half_width = view_size / 2
    half_height = half_width / aspect
    
    view_box = db.DBox(
        center_x - half_width,
        center_y - half_height,
        center_x + half_width,
        center_y + half_height
    )
    
    # Set the view
    lv.zoom_box(view_box)
    
    # Generate filename
    filename = os.path.join(OUTPUT_DIR, f"frame_{frame:04d}.png")
    
    # Save image
    lv.save_image(filename, IMAGE_WIDTH, IMAGE_HEIGHT)
    
    # Progress indicator
    progress = int((frame + 1) / NUM_FRAMES * 50)
    bar = "█" * progress + "░" * (50 - progress)
    zoom_level = MAX_VIEW_SIZE / view_size
    print(f"\r  [{bar}] {frame+1}/{NUM_FRAMES} - {view_size:.1f}µm ({zoom_level:.0f}x)", end="", flush=True)

print()  # New line after progress bar

# =============================================================================
# Summary
# =============================================================================

print("\n" + "="*70)
print("  ✓ Zoom sequence generation complete!")
print("="*70)

# Calculate total size
total_size = sum(os.path.getsize(os.path.join(OUTPUT_DIR, f)) 
                 for f in os.listdir(OUTPUT_DIR) if f.endswith('.png'))

print(f"""
  Output:
    • Directory: {OUTPUT_DIR}/
    • Frames: {NUM_FRAMES} PNG images
    • Resolution: {IMAGE_WIDTH} x {IMAGE_HEIGHT}
    • Total size: {total_size / 1024 / 1024:.1f} MB

  To create video, run:
    
    # Standard quality (smaller file)
    ffmpeg -framerate 30 -i {OUTPUT_DIR}/frame_%04d.png \\
           -c:v libx264 -pix_fmt yuv420p -crf 23 \\
           build/gpu_zoomout.mp4

    # High quality (larger file)
    ffmpeg -framerate 30 -i {OUTPUT_DIR}/frame_%04d.png \\
           -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow \\
           build/gpu_zoomout_hq.mp4

    # For smooth slow zoom (60fps, 4 seconds)
    ffmpeg -framerate 30 -i {OUTPUT_DIR}/frame_%04d.png \\
           -filter:v "minterpolate=fps=60:mi_mode=mci" \\
           -c:v libx264 -pix_fmt yuv420p -crf 18 \\
           build/gpu_zoomout_smooth.mp4

  Video duration: {NUM_FRAMES / 30:.1f} seconds at 30fps
""")
print("="*70)

