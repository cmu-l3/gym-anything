#!/bin/bash
# Export script for channel_montage_creation task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Channel Montage Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Define paths
RESULT_FILE="/home/ga/ImageJ_Data/results/fluorescence_montage.tif"
TASK_START_FILE="/tmp/task_start_timestamp"

# Use Python to inspect the image properties
# We need to verify it's a valid image, check dimensions (to prove it's a montage),
# and check stats (to prove it's not blank).
python3 << 'PYEOF'
import json
import os
import sys
import numpy as np
from PIL import Image

output = {
    "file_exists": False,
    "is_valid_image": False,
    "width": 0,
    "height": 0,
    "total_area": 0,
    "mode": "",
    "file_size_bytes": 0,
    "timestamp_valid": False,
    "pixel_mean": 0.0,
    "pixel_std": 0.0,
    "error": None
}

filepath = "/home/ga/ImageJ_Data/results/fluorescence_montage.tif"
start_time_file = "/tmp/task_start_timestamp"

try:
    if os.path.exists(filepath):
        output["file_exists"] = True
        output["file_size_bytes"] = os.path.getsize(filepath)
        
        # Check timestamp
        if os.path.exists(start_time_file):
            with open(start_time_file) as f:
                start_ts = float(f.read().strip())
            file_mtime = os.path.getmtime(filepath)
            # Allow 2 second buffer for file system skew
            output["timestamp_valid"] = file_mtime >= (start_ts - 2.0)
        else:
            # If no start time recorded, assume valid if file exists (fallback)
            output["timestamp_valid"] = True

        # Open image
        try:
            img = Image.open(filepath)
            output["is_valid_image"] = True
            output["width"] = img.size[0]
            output["height"] = img.size[1]
            output["total_area"] = img.size[0] * img.size[1]
            output["mode"] = img.mode
            
            # Check content (not blank)
            # Convert to numpy array
            arr = np.array(img, dtype=float)
            output["pixel_mean"] = float(arr.mean())
            output["pixel_std"] = float(arr.std())
            
        except Exception as e:
            output["error"] = f"Image open failed: {str(e)}"
    else:
        output["error"] = "File not found"

except Exception as e:
    output["error"] = f"Script error: {str(e)}"

# Save result to JSON
with open("/tmp/channel_montage_creation_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Export complete. Exists: {output['file_exists']}, Valid: {output['is_valid_image']}")
if output['is_valid_image']:
    print(f"Dimensions: {output['width']}x{output['height']}, StdDev: {output['pixel_std']:.2f}")
PYEOF

echo "=== Export Complete ==="