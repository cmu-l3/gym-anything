#!/bin/bash
# Export script for Kymograph Motility Analysis task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Kymograph Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Define paths
KYMO_FILE="/home/ga/ImageJ_Data/results/mitosis_kymograph.tif"
PROJ_FILE="/home/ga/ImageJ_Data/results/mitosis_projection.tif"
START_TIME_FILE="/tmp/task_start_timestamp"

# Use Python to analyze the output images (robust metadata extraction)
python3 << 'PYEOF'
import json
import os
import sys
from PIL import Image

output = {
    "kymo_exists": False,
    "kymo_width": 0,
    "kymo_height": 0,
    "kymo_created_after_start": False,
    "proj_exists": False,
    "proj_frames": 0,
    "proj_created_after_start": False,
    "task_start_time": 0
}

# Get task start time
try:
    with open("/tmp/task_start_timestamp", "r") as f:
        output["task_start_time"] = int(f.read().strip())
except:
    pass

# Analyze Kymograph File
kymo_path = "/home/ga/ImageJ_Data/results/mitosis_kymograph.tif"
if os.path.exists(kymo_path):
    output["kymo_exists"] = True
    # Check timestamp
    if os.path.getmtime(kymo_path) > output["task_start_time"]:
        output["kymo_created_after_start"] = True
    
    try:
        with Image.open(kymo_path) as img:
            output["kymo_width"] = img.width
            output["kymo_height"] = img.height
    except Exception as e:
        print(f"Error reading kymograph: {e}")

# Analyze Projection File
proj_path = "/home/ga/ImageJ_Data/results/mitosis_projection.tif"
if os.path.exists(proj_path):
    output["proj_exists"] = True
    if os.path.getmtime(proj_path) > output["task_start_time"]:
        output["proj_created_after_start"] = True
        
    try:
        with Image.open(proj_path) as img:
            # For a stack, we need to count frames
            frames = 1
            try:
                # PIL approach to counting frames in a stack
                while True:
                    img.seek(frames)
                    frames += 1
            except EOFError:
                pass
            output["proj_frames"] = frames
    except Exception as e:
        print(f"Error reading projection: {e}")

# Save result
with open("/tmp/kymograph_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Export complete.")
PYEOF

cat /tmp/kymograph_result.json
echo "=== Export Done ==="