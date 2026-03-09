#!/bin/bash
# Export script for stage_drift_correction task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Stage Drift Correction Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

RESULT_FILE="/home/ga/ImageJ_Data/results/stabilized_stack.tif"
INPUT_FILE="/home/ga/ImageJ_Data/raw/drifting_structure.tif"
TASK_START_FILE="/tmp/task_start_timestamp"

# We use Python to analyze the result image metrics inside the container
# This avoids needing complex image processing dependencies in the verifier
python3 << 'PYEOF'
import json
import os
import sys
import numpy as np
from PIL import Image, ImageSequence, ImageStat
from scipy import ndimage

output_path = "/home/ga/ImageJ_Data/results/stabilized_stack.tif"
input_path = "/home/ga/ImageJ_Data/raw/drifting_structure.tif"
task_start_file = "/tmp/task_start_timestamp"

result = {
    "file_exists": False,
    "file_size": 0,
    "is_stack": False,
    "frame_count": 0,
    "input_sharpness": 0.0,
    "output_sharpness": 0.0,
    "sharpness_ratio": 0.0,
    "content_correlation": 0.0,
    "file_created_during_task": False,
    "error": None
}

try:
    # Check timestamps
    task_start = 0
    if os.path.exists(task_start_file):
        with open(task_start_file, 'r') as f:
            task_start = int(f.read().strip())

    if os.path.exists(output_path):
        result["file_exists"] = True
        stats = os.stat(output_path)
        result["file_size"] = stats.st_size
        
        if stats.st_mtime > task_start:
            result["file_created_during_task"] = True
            
        # Analyze Images
        try:
            # Load Input (Reference)
            in_img = Image.open(input_path)
            in_frames = [np.array(f.convert('L')) for f in ImageSequence.Iterator(in_img)]
            
            # Load Output
            out_img = Image.open(output_path)
            out_frames = [np.array(f.convert('L')) for f in ImageSequence.Iterator(out_img)]
            
            result["frame_count"] = len(out_frames)
            result["is_stack"] = len(out_frames) > 1
            
            if result["is_stack"]:
                # 1. Calculate Average Projections
                in_avg = np.mean(in_frames, axis=0)
                out_avg = np.mean(out_frames, axis=0)
                
                # 2. Calculate Sharpness (Gradient Magnitude Mean)
                # A blurry average (drifting) has low gradients
                # A sharp average (stabilized) has high gradients
                def get_sharpness(img_arr):
                    sx = ndimage.sobel(img_arr, axis=0, mode='constant')
                    sy = ndimage.sobel(img_arr, axis=1, mode='constant')
                    return float(np.mean(np.hypot(sx, sy)))

                result["input_sharpness"] = get_sharpness(in_avg)
                result["output_sharpness"] = get_sharpness(out_avg)
                
                if result["input_sharpness"] > 0:
                    result["sharpness_ratio"] = result["output_sharpness"] / result["input_sharpness"]
                
                # 3. Content Check (Correlation)
                # Compare center of first frame of input vs output
                # to ensure they didn't just save a different image
                # Resize output to input size if needed
                h, w = in_frames[0].shape
                out_first = Image.fromarray(out_frames[0]).resize((w, h))
                out_arr = np.array(out_first)
                
                # Simple correlation coefficient
                flat_in = in_frames[0].flatten()
                flat_out = out_arr.flatten()
                corr = np.corrcoef(flat_in, flat_out)[0, 1]
                result["content_correlation"] = float(corr)
                
        except Exception as e:
            result["error"] = f"Image analysis failed: {str(e)}"
            
except Exception as e:
    result["error"] = str(e)

# Save result
with open("/tmp/stage_drift_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

echo "=== Export Complete ==="