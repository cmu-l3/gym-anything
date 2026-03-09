#!/bin/bash
set -e
echo "=== Setting up Tile Stitching Task ==="

# 1. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 2. Prepare Directories
DATA_DIR="/home/ga/Fiji_Data/raw/tiles"
RESULT_DIR="/home/ga/Fiji_Data/results/stitched"

# Create directories as user ga
su - ga -c "mkdir -p '$DATA_DIR'"
su - ga -c "mkdir -p '$RESULT_DIR'"

# Clean up any previous results
rm -f "$RESULT_DIR"/* 2>/dev/null || true
rm -f "$DATA_DIR"/* 2>/dev/null || true

# 3. Download Source Image (Official ImageJ Sample)
# We use the FluorescentCells sample (RGB) or a fallback
SOURCE_IMG="/tmp/source_image.jpg"
echo "Downloading source image..."
wget -q --timeout=30 "https://imagej.nih.gov/ij/images/FluorescentCells.jpg" -O "$SOURCE_IMG" || \
wget -q --timeout=30 "https://imagej.net/images/FluorescentCells.jpg" -O "$SOURCE_IMG" || \
wget -q --timeout=30 "https://imagej.nih.gov/ij/images/leaf.jpg" -O "$SOURCE_IMG"

if [ ! -f "$SOURCE_IMG" ] || [ ! -s "$SOURCE_IMG" ]; then
    echo "ERROR: Failed to download source image."
    exit 1
fi

# 4. Generate Tiles using Python
# We generate 3x3 tiles with overlap
echo "Generating tiles..."
python3 << PYEOF
import os
from PIL import Image
import math

source_path = "$SOURCE_IMG"
output_dir = "$DATA_DIR"

try:
    img = Image.open(source_path)
    # Ensure standard RGB
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    W, H = img.size
    print(f"Source Image Size: {W}x{H}")

    grid_x, grid_y = 3, 3
    overlap_pct = 0.15

    # Calculate tile size based on total size, grid, and overlap
    # Formula: Total = tile + (grid-1)*(tile*(1-overlap))
    # Total = tile * (1 + (grid-1)*(1-overlap))
    # tile = Total / (1 + (grid-1)*(1-overlap))
    
    denom_x = 1 + (grid_x - 1) * (1 - overlap_pct)
    denom_y = 1 + (grid_y - 1) * (1 - overlap_pct)
    
    tile_w = int(math.ceil(W / denom_x))
    tile_h = int(math.ceil(H / denom_y))
    
    print(f"Calculated Tile Size: {tile_w}x{tile_h}")
    
    # Stride
    stride_x = int(tile_w * (1 - overlap_pct))
    stride_y = int(tile_h * (1 - overlap_pct))

    idx = 1
    tile_stats = []
    
    for row in range(grid_y):
        for col in range(grid_x):
            x = col * stride_x
            y = row * stride_y
            
            # Clamp to image bounds
            box = (x, y, x + tile_w, y + tile_h)
            
            # Crop
            tile = img.crop(box)
            
            # Save
            filename = f"tile_{idx}.tif"
            filepath = os.path.join(output_dir, filename)
            tile.save(filepath)
            
            # Record dimensions for validation logic
            tile_stats.append(f"{idx},{tile.width},{tile.height}")
            idx += 1
            
    # Save tile stats for setup verification
    with open("/tmp/tile_setup_stats.txt", "w") as f:
        f.write("\n".join(tile_stats))
        
except Exception as e:
    print(f"Error generating tiles: {e}")
    exit(1)
PYEOF

# 5. Create Metadata File
cat > "$DATA_DIR/grid_info.txt" << EOF
grid_size_x=3
grid_size_y=3
tile_overlap_percent=15
tile_order=Right & Down
first_file_index=1
filename_pattern=tile_{i}.tif
EOF

# Set permissions
chown -R ga:ga "/home/ga/Fiji_Data"

# 6. Launch Fiji
echo "Launching Fiji..."
# Check if launch script exists (from env setup), else try direct
if [ -f "/home/ga/launch_fiji.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
else
    # Fallback
    su - ga -c "DISPLAY=:1 /usr/local/bin/fiji" &
fi

# Wait for window
echo "Waiting for Fiji window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
        echo "Fiji window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus
DISPLAY=:1 wmctrl -a "Fiji" 2>/dev/null || true

# 7. Take Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="