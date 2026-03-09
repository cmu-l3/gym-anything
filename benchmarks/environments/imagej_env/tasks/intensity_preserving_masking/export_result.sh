#!/bin/bash
# Export script for intensity_preserving_masking task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Masking Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Run Python analysis on the output file
python3 << 'PYEOF'
import json
import os
import numpy as np
from PIL import Image

output_path = "/home/ga/ImageJ_Data/results/masked_blobs.tif"
result_json_path = "/tmp/masking_result.json"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "is_grayscale": False,
    "unique_pixel_values": 0,
    "percent_zeros": 0.0,
    "mean_intensity_nonzero": 0.0,
    "is_binary": False,
    "task_valid_timestamp": False,
    "error": None
}

# Check timestamp
try:
    if os.path.exists(output_path) and os.path.exists(task_start_file):
        start_time = int(open(task_start_file).read().strip())
        mod_time = int(os.path.getmtime(output_path))
        if mod_time > start_time:
            output["task_valid_timestamp"] = True
except Exception:
    pass

if os.path.exists(output_path):
    output["file_exists"] = True
    output["file_size_bytes"] = os.path.getsize(output_path)
    
    try:
        img = Image.open(output_path)
        # Convert to numpy array
        arr = np.array(img)
        
        # Check mode
        if img.mode == 'L' or len(arr.shape) == 2:
            output["is_grayscale"] = True
        
        # Analyze pixels
        unique_vals = np.unique(arr)
        output["unique_pixel_values"] = len(unique_vals)
        
        # Check if binary
        if len(unique_vals) <= 2:
            output["is_binary"] = True
            
        # Calculate percentage of background (0)
        total_pixels = arr.size
        zero_pixels = np.sum(arr == 0)
        output["percent_zeros"] = float(zero_pixels) / total_pixels * 100.0
        
        # Calculate mean of foreground (non-zero)
        # In Blobs sample, particles are dark (~40-60). 
        # If they masked correctly, non-zeros should be around there.
        # If they inverted/thresholded to white, non-zeros will be 255.
        if total_pixels > zero_pixels:
            output["mean_intensity_nonzero"] = float(np.mean(arr[arr > 0]))
            
    except Exception as e:
        output["error"] = str(e)

with open(result_json_path, "w") as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
PYEOF

echo "=== Export Complete ==="