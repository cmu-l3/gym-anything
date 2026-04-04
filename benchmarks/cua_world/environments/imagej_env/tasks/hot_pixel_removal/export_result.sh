#!/bin/bash
# Export script for Hot Pixel Removal task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Hot Pixel Removal Result ==="

# Directories
INPUT_FILE="/home/ga/ImageJ_Data/raw/noisy_galaxy.tif"
OUTPUT_FILE="/home/ga/ImageJ_Data/results/clean_galaxy.tif"
GT_FILE="/var/lib/imagej/ground_truth/clean_galaxy_gt.tif"
TASK_START_FILE="/tmp/task_start_timestamp"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Analyze results using Python
# We calculate metrics directly here to avoid passing large images to verifier
# The verifier.py will read the JSON stats
python3 << 'EOF'
import json
import os
import numpy as np
from PIL import Image
import sys

output = {
    "file_exists": False,
    "file_created_during_task": False,
    "is_16bit": False,
    "hot_pixel_count": -1,
    "input_hot_pixel_count": -1,
    "mse_vs_gt": -1.0,
    "blurriness_ratio": -1.0, # Ratio of output laplacian var / gt laplacian var
    "dimensions_match": False,
    "error": None
}

input_path = "/home/ga/ImageJ_Data/raw/noisy_galaxy.tif"
output_path = "/home/ga/ImageJ_Data/results/clean_galaxy.tif"
gt_path = "/var/lib/imagej/ground_truth/clean_galaxy_gt.tif"
task_start_path = "/tmp/task_start_timestamp"

try:
    # Check timestamps
    task_start = 0
    if os.path.exists(task_start_path):
        with open(task_start_path, 'r') as f:
            task_start = int(f.read().strip())

    if os.path.exists(output_path):
        output["file_exists"] = True
        mtime = os.path.getmtime(output_path)
        if mtime > task_start:
            output["file_created_during_task"] = True
        
        # Load Images
        try:
            img_out = Image.open(output_path)
            img_in = Image.open(input_path)
            img_gt = Image.open(gt_path)
            
            # Check format
            if img_out.mode == 'I;16' or img_out.mode == 'I' or img_out.mode == 'F':
                # PIL handles 16-bit tiffs weirdly sometimes, usually 'I;16'
                output["is_16bit"] = True
            
            # Convert to numpy for analysis
            arr_out = np.array(img_out).astype(np.float64)
            arr_in = np.array(img_in).astype(np.float64)
            arr_gt = np.array(img_gt).astype(np.float64)
            
            # Check dimensions
            if arr_out.shape == arr_gt.shape:
                output["dimensions_match"] = True
            
            # 1. Count Hot Pixels (Value 65535 in 16-bit)
            # Threshold slightly below max to catch potential minor resampling artifacts
            hot_threshold = 65000 
            output["hot_pixel_count"] = int(np.sum(arr_out >= hot_threshold))
            output["input_hot_pixel_count"] = int(np.sum(arr_in >= hot_threshold))
            
            # 2. MSE vs Ground Truth (Measure of restoration quality)
            # Only calculate on non-hot-pixel locations of the input to see preservation?
            # Or just global MSE. Global MSE is fine since GT is clean.
            mse = np.mean((arr_out - arr_gt) ** 2)
            output["mse_vs_gt"] = float(mse)
            
            # 3. Blurriness Check (Laplacian Variance)
            # High variance = sharp edges. Low variance = blurry.
            # We want output sharpness to be close to GT sharpness, not significantly lower.
            import scipy.ndimage
            lap_out = scipy.ndimage.laplace(arr_out)
            lap_gt = scipy.ndimage.laplace(arr_gt)
            var_out = np.var(lap_out)
            var_gt = np.var(lap_gt)
            
            if var_gt > 0:
                output["blurriness_ratio"] = float(var_out / var_gt)
            else:
                output["blurriness_ratio"] = 0.0
                
        except Exception as e:
            output["error"] = f"Image processing error: {str(e)}"
            
except Exception as e:
    output["error"] = f"General error: {str(e)}"

with open("/tmp/hot_pixel_result.json", "w") as f:
    json.dump(output, f, indent=2)

print("Export script finished.")
EOF

echo "=== Export Complete ==="