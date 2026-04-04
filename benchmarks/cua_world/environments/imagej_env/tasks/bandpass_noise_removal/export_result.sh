#!/bin/bash
echo "=== Exporting Bandpass Noise Removal Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
NOISY_IMG="/home/ga/ImageJ_Data/raw/noisy_blobs.tif"
FILTERED_IMG="/home/ga/ImageJ_Data/results/filtered_image.tif"
CSV_FILE="/home/ga/ImageJ_Data/results/bandpass_filter_results.csv"
GROUND_TRUTH="/var/lib/imagej_ground_truth/clean_reference.tif"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Analyze results using Python
python3 << PYEOF
import json
import os
import sys
import csv
import numpy as np
from PIL import Image
try:
    from skimage.metrics import structural_similarity as ssim
    SKIMAGE_AVAIL = True
except ImportError:
    SKIMAGE_AVAIL = False

result = {
    "timestamp": $TASK_END,
    "task_start": $TASK_START,
    "filtered_image_exists": False,
    "csv_exists": False,
    "metrics": {}
}

# 1. Analyze Images
try:
    if os.path.exists("$FILTERED_IMG"):
        # Check timestamp
        mtime = os.path.getmtime("$FILTERED_IMG")
        if mtime > result["task_start"]:
            result["filtered_image_exists"] = True
            
            # Load images
            noisy = np.array(Image.open("$NOISY_IMG").convert("L"), dtype=np.float64)
            filtered = np.array(Image.open("$FILTERED_IMG").convert("L"), dtype=np.float64)
            
            # Load GT if available
            gt = None
            if os.path.exists("$GROUND_TRUTH"):
                gt = np.array(Image.open("$GROUND_TRUTH").convert("L"), dtype=np.float64)
            
            # Calculate basic stats
            result["metrics"]["noisy_std"] = float(np.std(noisy))
            result["metrics"]["filtered_std"] = float(np.std(filtered))
            result["metrics"]["noisy_mean"] = float(np.mean(noisy))
            result["metrics"]["filtered_mean"] = float(np.mean(filtered))
            
            # Calculate SSIM if possible
            if gt is not None and SKIMAGE_AVAIL:
                # Ensure shapes match
                if filtered.shape == gt.shape:
                    score_noisy = ssim(noisy, gt, data_range=255)
                    score_filtered = ssim(filtered, gt, data_range=255)
                    result["metrics"]["ssim_noisy"] = float(score_noisy)
                    result["metrics"]["ssim_filtered"] = float(score_filtered)
                    result["metrics"]["ssim_improvement"] = float(score_filtered - score_noisy)

except Exception as e:
    result["image_error"] = str(e)

# 2. Analyze CSV
try:
    if os.path.exists("$CSV_FILE"):
        mtime = os.path.getmtime("$CSV_FILE")
        if mtime > result["task_start"]:
            result["csv_exists"] = True
            
            rows = []
            with open("$CSV_FILE", 'r') as f:
                reader = csv.reader(f)
                rows = list(reader)
            
            result["csv_row_count"] = len(rows)
            result["csv_content_sample"] = rows[:5]
            
            # Check for required keywords
            content = open("$CSV_FILE").read().lower()
            result["csv_has_std"] = any(x in content for x in ['std', 'dev', 'standard'])
            result["csv_has_mean"] = 'mean' in content
            
except Exception as e:
    result["csv_error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="