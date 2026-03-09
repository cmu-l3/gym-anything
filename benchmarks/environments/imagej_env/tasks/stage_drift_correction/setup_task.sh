#!/bin/bash
# Setup script for stage_drift_correction task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Stage Drift Correction Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RAW_DIR="$DATA_DIR/raw"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RAW_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear previous results
rm -f "$RESULTS_DIR/stabilized_stack.tif" 2>/dev/null || true
rm -f /tmp/stage_drift_result.json 2>/dev/null || true
rm -f "$RAW_DIR/drifting_structure.tif" 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ============================================================
# Generate Drifting Stack using Python
# ============================================================
echo "Generating drifting image stack..."

cat > /tmp/generate_drift.py << 'PYEOF'
import numpy as np
from PIL import Image, ImageChops, ImageDraw
import os
import urllib.request
import sys

def generate_drift():
    output_path = "/home/ga/ImageJ_Data/raw/drifting_structure.tif"
    
    # Create a synthetic texture image if download fails
    width, height = 512, 512
    img = Image.new('L', (width, height), color=0)
    
    # Try to download the standard 'bridge' image
    try:
        url = "https://imagej.nih.gov/ij/images/bridge.gif"
        local_src = "/tmp/bridge.gif"
        if not os.path.exists(local_src):
            print(f"Downloading {url}...")
            urllib.request.urlretrieve(url, local_src)
        img = Image.open(local_src).convert('L')
        print("Loaded standard Bridge image.")
    except Exception as e:
        print(f"Download failed ({e}), generating synthetic texture...")
        # Generate noise texture
        arr = np.random.randint(0, 255, (height, width), dtype=np.uint8)
        img = Image.fromarray(arr)
        # Add some geometric shapes for registration features
        draw = ImageDraw.Draw(img)
        draw.rectangle([100, 100, 200, 200], fill=200)
        draw.ellipse([300, 300, 400, 400], fill=150)
        draw.line([0, 0, 512, 512], fill=255, width=5)

    # Parameters for drift
    n_frames = 30
    crop_w, crop_h = 350, 350
    
    # Ensure source is large enough
    if img.width < crop_w + 60 or img.height < crop_h + 60:
        img = img.resize((max(img.width, crop_w+100), max(img.height, crop_h+100)))

    # Drift trajectory: Linear drift
    # Start near top-left, move down-right
    start_x, start_y = 10, 10
    drift_x, drift_y = 2, 2  # pixels per frame
    
    frames = []
    print(f"Generating {n_frames} frames with drift...")
    
    for i in range(n_frames):
        # Calculate window position
        x = int(start_x + (i * drift_x))
        y = int(start_y + (i * drift_y))
        
        # Crop
        box = (x, y, x + crop_w, y + crop_h)
        frame = img.crop(box)
        frames.append(frame)
        
    # Save as multipage TIFF
    print(f"Saving to {output_path}")
    frames[0].save(output_path, save_all=True, append_images=frames[1:], compression="tiff_deflate")
    print("Generation complete.")

if __name__ == "__main__":
    generate_drift()
PYEOF

python3 /tmp/generate_drift.py

if [ ! -f "$RAW_DIR/drifting_structure.tif" ]; then
    echo "ERROR: Failed to generate input file"
    exit 1
fi

chown ga:ga "$RAW_DIR/drifting_structure.tif"

# ============================================================
# Kill existing Fiji
# ============================================================
kill_fiji 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Open ~/ImageJ_Data/raw/drifting_structure.tif and stabilize it."
echo "Save result to ~/ImageJ_Data/results/stabilized_stack.tif"