#!/bin/bash
echo "=== Exporting Stitching Results ==="

# 1. Configuration
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_TIF="/home/ga/Fiji_Data/results/stitched/stitched_panorama.tif"
RESULT_PNG="/home/ga/Fiji_Data/results/stitched/stitched_panorama.png"
TILE_DIR="/home/ga/Fiji_Data/raw/tiles"

# 2. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Analyze Output with Python
# We need to extract dimensions, timestamps, and check if content is not empty
python3 << PYEOF
import os
import json
import sys
import time
from PIL import Image
import numpy as np

result = {
    "tif_exists": False,
    "png_exists": False,
    "tif_created_during_task": False,
    "png_created_during_task": False,
    "width": 0,
    "height": 0,
    "mean_intensity": 0.0,
    "is_single_tile": False,
    "aspect_ratio": 0.0,
    "timestamp": time.time()
}

task_start = int("$TASK_START")
tif_path = "$RESULT_TIF"
png_path = "$RESULT_PNG"
tile_dir = "$TILE_DIR"

# Check TIFF
if os.path.exists(tif_path):
    result["tif_exists"] = True
    mtime = os.path.getmtime(tif_path)
    if mtime > task_start:
        result["tif_created_during_task"] = True
    
    try:
        img = Image.open(tif_path)
        result["width"] = img.width
        result["height"] = img.height
        result["aspect_ratio"] = img.width / img.height if img.height > 0 else 0
        
        # Calculate mean intensity (check for black image)
        arr = np.array(img)
        result["mean_intensity"] = float(np.mean(arr))
        
        # Check against single tile size (Anti-Gaming)
        # Load one tile to compare
        tile_path = os.path.join(tile_dir, "tile_1.tif")
        if os.path.exists(tile_path):
            tile = Image.open(tile_path)
            # If output is roughly the same size as a single tile (+- 5%)
            if abs(img.width - tile.width) < tile.width * 0.05 and \
               abs(img.height - tile.height) < tile.height * 0.05:
                result["is_single_tile"] = True
                
    except Exception as e:
        result["error_tif"] = str(e)

# Check PNG
if os.path.exists(png_path):
    result["png_exists"] = True
    mtime = os.path.getmtime(png_path)
    if mtime > task_start:
        result["png_created_during_task"] = True

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PYEOF

# 4. Cleanup Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="