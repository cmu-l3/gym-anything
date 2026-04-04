#!/bin/bash
set -e
echo "=== Setting up Botanical Morphometry Task ==="

# 1. Create Directories
RAW_DIR="/home/ga/Fiji_Data/raw/botany"
RES_DIR="/home/ga/Fiji_Data/results/botany"
GT_DIR="/var/lib/app/ground_truth"

mkdir -p "$RAW_DIR" "$RES_DIR" "$GT_DIR"
chown -R ga:ga "/home/ga/Fiji_Data"

# 2. Record Start Time
date +%s > /tmp/task_start_time.txt

# 3. Generate Randomized Dataset (Python)
# We use Python to download a leaf, randomly resize it, add a reference bar of random length,
# and calculate the ground truth area based on that specific random instance.
cat << 'EOF' > /tmp/generate_leaf.py
import os
import sys
import random
import numpy as np
import requests
from io import BytesIO
from PIL import Image, ImageDraw, ImageFont, ImageOps

def generate_task_data():
    # Candidates for public domain/CC0 leaf images
    leaf_urls = [
        "https://upload.wikimedia.org/wikipedia/commons/thumb/9/97/Tilia-cordata-leaf-1.jpg/800px-Tilia-cordata-leaf-1.jpg", 
        "https://upload.wikimedia.org/wikipedia/commons/thumb/e/eb/Populus_tremula_leaf.jpg/607px-Populus_tremula_leaf.jpg",
        "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/Leaf_1_web.jpg/640px-Leaf_1_web.jpg"
    ]
    
    # Try downloading, fallback to synthetic if fails
    img = None
    try:
        url = random.choice(leaf_urls)
        print(f"Downloading {url}...")
        resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            img = Image.open(BytesIO(resp.content)).convert("RGB")
    except Exception as e:
        print(f"Download failed: {e}")
    
    # Synthetic fallback
    if img is None:
        print("Generating synthetic leaf...")
        img = Image.new("RGB", (800, 800), (255, 255, 255))
        draw = ImageDraw.Draw(img)
        # Draw a green ellipse-like shape
        draw.ellipse([200, 100, 600, 700], fill=(34, 139, 34))

    # Random Resize (0.6x to 1.4x) - This changes pixel counts
    scale_factor = random.uniform(0.6, 1.4)
    new_w = int(img.width * scale_factor)
    new_h = int(img.height * scale_factor)
    img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    # Ensure white background is pure white for easier thresholding calculation
    # Simple binarization for ground truth calculation
    arr = np.array(img)
    # Heuristic: pixels significantly darker than white are leaf
    # Calculate grayscale
    gray = 0.299 * arr[:,:,0] + 0.587 * arr[:,:,1] + 0.114 * arr[:,:,2]
    # Threshold: Assuming white background > 200, leaf < 200
    mask = gray < 220
    leaf_pixel_count = np.sum(mask)
    
    print(f"Leaf pixel count: {leaf_pixel_count}")
    
    # Determine Reference Line Scale
    # We define that a line of length L pixels = 2 cm
    # Randomize L between 100 and 400 pixels
    ref_px = random.randint(150, 400)
    pixels_per_cm = ref_px / 2.0
    
    print(f"Reference: {ref_px} pixels = 2 cm ({pixels_per_cm} px/cm)")
    
    # Calculate Ground Truth Area (cm^2)
    ground_truth_area = leaf_pixel_count / (pixels_per_cm ** 2)
    print(f"Ground Truth Area: {ground_truth_area:.4f} cm^2")
    
    # Save Ground Truth
    with open("/var/lib/app/ground_truth/botany_truth.json", "w") as f:
        f.write(f'{{"area_cm2": {ground_truth_area}, "pixels_per_cm": {pixels_per_cm}, "leaf_pixels": {int(leaf_pixel_count)}}}')
        
    # Draw Reference Line on Image
    draw = ImageDraw.Draw(img)
    # Position: Bottom left quadrant, avoiding the leaf if possible
    # We'll just put it in a fixed safe spot relative to image size, typically top left or bottom left
    margin = 50
    start_x = margin
    start_y = img.height - margin - 50
    end_x = start_x + ref_px
    end_y = start_y
    
    # Draw thick black line
    draw.line([(start_x, start_y), (end_x, end_y)], fill="black", width=5)
    
    # Add Text
    try:
        # Default font
        draw.text((start_x, start_y - 20), "Reference: 2 cm", fill="black")
    except:
        pass
        
    # Save Task Image
    img.save("/home/ga/Fiji_Data/raw/botany/leaf_specimen.jpg", quality=95)

if __name__ == "__main__":
    generate_task_data()
EOF

python3 /tmp/generate_leaf.py

# 4. Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" > /dev/null 2>&1 &
sleep 10

# 5. Window Management
echo "Configuring window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej"; then
        DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
        DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="