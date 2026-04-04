#!/bin/bash
# Export script for Internal Void Segmentation task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Void Segmentation Result ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Define Paths
RESULT_FILE="/home/ga/ImageJ_Data/results/void_mask.tif"
TASK_START_FILE="/tmp/task_start_time"

# 3. Analyze output using Python
# We do this inside the VM to package metadata for the verifier
# This avoids dependencies on the host side for basic file checks
python3 << 'PYEOF'
import json
import os
import sys
import time

result_path = "/home/ga/ImageJ_Data/results/void_mask.tif"
task_start_path = "/tmp/task_start_time"
output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "file_created_after_start": False,
    "dimensions": None,
    "foreground_ratio": 0.0,
    "is_binary": False,
    "timestamp": int(time.time())
}

# Check timestamp
start_time = 0
try:
    with open(task_start_path, 'r') as f:
        start_time = int(f.read().strip())
except:
    pass

if os.path.exists(result_path):
    output["file_exists"] = True
    stats = os.stat(result_path)
    output["file_size_bytes"] = stats.st_size
    
    # Check modification time
    if stats.st_mtime > start_time:
        output["file_created_after_start"] = True
        
    # Basic Image Analysis using PIL/Pillow
    try:
        from PIL import Image
        import numpy as np
        
        with Image.open(result_path) as img:
            output["dimensions"] = img.size
            
            # Convert to numpy for analysis
            arr = np.array(img)
            
            # Check for binary content (only 0 and 255/1 allowed)
            unique_vals = np.unique(arr)
            # Allow some compression artifacts if not perfect binary, but ideally just 2 values
            if len(unique_vals) <= 2:
                output["is_binary"] = True
            elif len(unique_vals) < 10: 
                # Relaxed check for anti-aliasing or compression
                output["is_binary"] = True
                
            # Calculate foreground ratio (pixels > 0)
            # In the Blobs image, holes are a small fraction of the total area.
            # Blobs themselves are ~30-40%. Holes are much less.
            total_pixels = arr.size
            foreground_pixels = np.count_nonzero(arr > 128) # Threshold mid-way
            output["foreground_ratio"] = foreground_pixels / total_pixels
            
    except Exception as e:
        output["error"] = str(e)

with open("/tmp/void_segmentation_result.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"Exported metrics: Exists={output['file_exists']}, Ratio={output['foreground_ratio']:.4f}")
PYEOF

echo "=== Export Complete ==="