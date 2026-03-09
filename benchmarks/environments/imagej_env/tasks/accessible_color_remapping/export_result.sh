#!/bin/bash
# Export script for accessible_color_remapping task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Remapping Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Define paths
OUTPUT_FILE="/home/ga/ImageJ_Data/results/accessible_composite.tif"
GT_FILE="/var/lib/imagej/ground_truth_cells.jpg"
JSON_OUT="/tmp/remapping_analysis.json"
TASK_START_FILE="/tmp/task_start_timestamp"

# 3. Run Python Analysis Script inside the container
# This calculates channel correlations between the agent's output and the ground truth
# We do this here because the container has the necessary image libraries installed

python3 << 'PYEOF'
import json
import os
import sys
import numpy as np
from PIL import Image

output_path = "/home/ga/ImageJ_Data/results/accessible_composite.tif"
gt_path = "/var/lib/imagej/ground_truth_cells.jpg"
json_path = "/tmp/remapping_analysis.json"
task_start_path = "/tmp/task_start_timestamp"

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "dimensions_match": False,
    "correlations": {
        "out_R_vs_gt_R": 0.0,
        "out_G_vs_gt_G": 0.0,
        "out_B_vs_gt_B": 0.0,
        "out_B_vs_gt_R": 0.0,  # Crucial for Magenta check (Magenta = R+B)
        "out_G_vs_gt_R": 0.0   # Sanity check
    },
    "error": None
}

try:
    # Check file existence and timestamp
    if os.path.exists(output_path):
        result["file_exists"] = True
        
        # Check timestamp
        mtime = os.path.getmtime(output_path)
        try:
            with open(task_start_path, 'r') as f:
                start_time = float(f.read().strip())
            if mtime > start_time:
                result["file_created_during_task"] = True
        except:
            pass # Ignore timestamp error, verification can double check

        # Open Images
        try:
            img_out = Image.open(output_path).convert("RGB")
            img_gt = Image.open(gt_path).convert("RGB")
            
            # Check dimensions
            if img_out.size == img_gt.size:
                result["dimensions_match"] = True
                
                # Convert to numpy arrays for correlation
                # Normalize to 0-1
                arr_out = np.array(img_out) / 255.0
                arr_gt = np.array(img_gt) / 255.0
                
                # Extract channels
                # Shape is (H, W, 3) -> R=0, G=1, B=2
                out_R = arr_out[:,:,0].flatten()
                out_G = arr_out[:,:,1].flatten()
                out_B = arr_out[:,:,2].flatten()
                
                gt_R = arr_gt[:,:,0].flatten()
                gt_G = arr_gt[:,:,1].flatten()
                gt_B = arr_gt[:,:,2].flatten()
                
                # Calculate Correlations
                # np.corrcoef returns matrix, [0,1] is the value we want
                result["correlations"]["out_R_vs_gt_R"] = float(np.corrcoef(out_R, gt_R)[0,1])
                result["correlations"]["out_G_vs_gt_G"] = float(np.corrcoef(out_G, gt_G)[0,1])
                result["correlations"]["out_B_vs_gt_B"] = float(np.corrcoef(out_B, gt_B)[0,1])
                
                # Verification logic: 
                # If Red mapped to Magenta, the Red signal should appear in BOTH Red and Blue output channels
                # So Out_B should correlate with GT_R
                result["correlations"]["out_B_vs_gt_R"] = float(np.corrcoef(out_B, gt_R)[0,1])
                
                # Sanity: Out_G should NOT correlate strongly with GT_R (unless data is inherently correlated)
                result["correlations"]["out_G_vs_gt_R"] = float(np.corrcoef(out_G, gt_R)[0,1])
                
            else:
                result["error"] = f"Dimension mismatch: Output {img_out.size} vs GT {img_gt.size}"
                
        except Exception as e:
            result["error"] = f"Image processing error: {str(e)}"
    else:
        result["error"] = "Output file not found"

except Exception as e:
    result["error"] = f"Script error: {str(e)}"

# Save result
with open(json_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Analysis complete. Metrics saved to {json_path}")
PYEOF

echo "=== Export Complete ==="