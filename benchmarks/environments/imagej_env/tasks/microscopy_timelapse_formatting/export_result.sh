#!/bin/bash
# Export script for Microscopy Time-Lapse Formatting task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Task Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Python script to analyze the output image properties
python3 << 'PYEOF'
import json
import os
import sys
from PIL import Image, ImageStat
import numpy as np

output_path = "/home/ga/ImageJ_Data/processed/mitosis_movie_formatted.tif"
task_start_file = "/tmp/task_start_timestamp"

result = {
    "file_exists": False,
    "file_size": 0,
    "file_created_after_start": False,
    "width": 0,
    "height": 0,
    "n_frames": 0,
    "mode": "unknown",
    "timestamp_detected": False,
    "mean_intensity": 0,
    "error": None
}

try:
    # Check timestamp
    start_time = 0
    if os.path.exists(task_start_file):
        with open(task_start_file, 'r') as f:
            start_time = int(f.read().strip())

    if os.path.exists(output_path):
        result["file_exists"] = True
        stats = os.stat(output_path)
        result["file_size"] = stats.st_size
        result["file_created_after_start"] = stats.st_mtime > start_time

        try:
            with Image.open(output_path) as img:
                result["width"] = img.width
                result["height"] = img.height
                result["mode"] = img.mode
                
                # Count frames
                n_frames = 1
                try:
                    while True:
                        img.seek(n_frames)
                        n_frames += 1
                except EOFError:
                    pass
                result["n_frames"] = n_frames

                # Check for timestamp in top-left corner
                # We check frame 0. Timestamp is usually white text on background.
                img.seek(0)
                # Convert to grayscale numpy array
                arr = np.array(img.convert('L'))
                
                # Global mean intensity
                result["mean_intensity"] = float(np.mean(arr))
                
                # Check top-left 50x30 region for high contrast/white pixels
                # The raw image background is dark.
                tl_region = arr[0:30, 0:60]
                tl_max = np.max(tl_region)
                tl_mean = np.mean(tl_region)
                
                # If we have very bright pixels in TL that are significantly brighter than global mean
                # (Raw mitosis image has some bright spots, but text is pure white/yellow usually 255)
                # We check if max is near saturation (for 8-bit)
                if tl_max > 200 and tl_mean > (result["mean_intensity"] * 1.1):
                    result["timestamp_detected"] = True
                    
        except Exception as e:
            result["error"] = f"Image analysis error: {str(e)}"
    
except Exception as e:
    result["error"] = str(e)

with open("/tmp/mitosis_task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="