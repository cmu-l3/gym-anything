#!/bin/bash
# Export script for Standardized Patch Montage task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Task Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Analyze Output File
OUTPUT_FILE="/home/ga/ImageJ_Data/results/blobs_montage.png"
TASK_START_FILE="/tmp/task_start_timestamp"

# Use Python to analyze the image file and timestamps
python3 << 'PYEOF'
import json
import os
import sys
from PIL import Image

output_path = "/home/ga/ImageJ_Data/results/blobs_montage.png"
start_time_path = "/tmp/task_start_timestamp"

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "width": 0,
    "height": 0,
    "format": "unknown",
    "is_grayscale": False,
    "is_blank": True,
    "error": None
}

try:
    # Check timestamp
    task_start = 0
    if os.path.exists(start_time_path):
        with open(start_time_path, 'r') as f:
            task_start = int(f.read().strip())

    if os.path.exists(output_path):
        result["file_exists"] = True
        mtime = os.path.getmtime(output_path)
        
        if mtime > task_start:
            result["file_created_during_task"] = True
            
        # Analyze Image Content
        try:
            with Image.open(output_path) as img:
                result["width"] = img.width
                result["height"] = img.height
                result["format"] = img.format
                
                # Check mode (Blobs is 8-bit grayscale)
                if img.mode in ['L', '1']:
                    result["is_grayscale"] = True
                elif img.mode == 'RGB':
                    # Check if it's actually grayscale content
                    stat = img.getextrema()
                    if stat[0] == stat[1] == stat[2]:
                        result["is_grayscale"] = True
                
                # Check content (not blank/solid color)
                extrema = img.getextrema()
                # For L mode, extrema is (min, max). For RGB it's ((min,max), (min,max), (min,max))
                if isinstance(extrema[0], tuple):
                    # RGB case
                    is_flat = all(e[0] == e[1] for e in extrema)
                else:
                    # Grayscale case
                    is_flat = (extrema[0] == extrema[1])
                
                result["is_blank"] = is_flat

        except Exception as e:
            result["error"] = f"Image analysis failed: {str(e)}"
            
except Exception as e:
    result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="