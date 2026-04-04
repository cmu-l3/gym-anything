#!/bin/bash
echo "=== Exporting SEM Restoration Result ==="

RESULTS_DIR="/home/ga/Fiji_Data/results/sem_restoration"
OUTPUT_FILE="$RESULTS_DIR/alloy_restored.tif"
INPUT_FILE="/home/ga/Fiji_Data/raw/sem_noise/alloy_noisy.tif"
GT_FILE="/var/lib/fiji/ground_truth/alloy_clean.tif"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if output exists
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Calculate Image Metrics (SSIM) using Python in the container
# We compute this here to ensure we use the exact libraries available and pass simple JSON back
echo "Calculating image metrics..."
python3 << PYEOF > /tmp/metrics.json
import json
import numpy as np
import os
from PIL import Image
from skimage.metrics import structural_similarity as ssim
from scipy.ndimage import gaussian_filter

results = {
    "ssim_restored": 0.0,
    "ssim_noisy": 0.0,
    "ssim_blur": 0.0,
    "calculation_success": False,
    "error": ""
}

try:
    output_path = "$OUTPUT_FILE"
    input_path = "$INPUT_FILE"
    gt_path = "$GT_FILE"
    
    if os.path.exists(output_path) and os.path.exists(gt_path) and os.path.exists(input_path):
        # Load images
        img_restored = np.array(Image.open(output_path).convert('L'))
        img_gt = np.array(Image.open(gt_path).convert('L'))
        img_noisy = np.array(Image.open(input_path).convert('L'))
        
        # Ensure dimensions match (crop to min if needed, though they should be same)
        min_h = min(img_restored.shape[0], img_gt.shape[0])
        min_w = min(img_restored.shape[1], img_gt.shape[1])
        
        img_restored = img_restored[:min_h, :min_w]
        img_gt = img_gt[:min_h, :min_w]
        img_noisy = img_noisy[:min_h, :min_w]
        
        # Calculate SSIM vs Ground Truth
        # Data range is 255 for uint8 images
        score_restored = ssim(img_gt, img_restored, data_range=255.0)
        score_noisy = ssim(img_gt, img_noisy, data_range=255.0)
        
        # Calculate Gaussian Blur Baseline (to detect lazy blurring)
        # Sigma=2.0 usually removes noise but kills detail
        img_blur = gaussian_filter(img_noisy, sigma=2.0)
        score_blur = ssim(img_gt, img_blur, data_range=255.0)
        
        results["ssim_restored"] = float(score_restored)
        results["ssim_noisy"] = float(score_noisy)
        results["ssim_blur"] = float(score_blur)
        results["calculation_success"] = True
    else:
        results["error"] = "One or more image files missing"

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results))
PYEOF

# Merge metrics into final JSON
# We use a temporary python script to merge the shell variables and the metrics json
python3 << PYEOF > /tmp/task_result.json
import json

try:
    with open("/tmp/metrics.json", "r") as f:
        metrics = json.load(f)
except:
    metrics = {}

result = {
    "output_exists": "$OUTPUT_EXISTS" == "true",
    "file_created_during_task": "$FILE_CREATED_DURING_TASK" == "true",
    "output_size_bytes": int("$OUTPUT_SIZE"),
    "metrics": metrics,
    "task_timestamp": "$TASK_START"
}

print(json.dumps(result, indent=2))
PYEOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json