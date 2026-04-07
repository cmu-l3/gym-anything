#!/bin/bash
echo "=== Exporting generate_finding_chart task results ==="

source /workspace/scripts/task_utils.sh

# Capture the final state screenshot for VLM analysis
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# We use a Python script to robustly analyze the scientific (FITS) and visual (PNG) outputs.
# This avoids brittle bash parsing and ensures we accurately check image dimensions and statistics.
cat > /tmp/analyze_outputs.py << 'EOF'
import os
import sys
import json
import numpy as np

start_time = int(sys.argv[1])
task_end = int(sys.argv[2])

fits_path = "/home/ga/AstroImages/processed/m12_core_crop.fits"
png_path = "/home/ga/AstroImages/processed/m12_core_finding_chart.png"

result = {
    "task_start": start_time,
    "task_end": task_end,
    "fits_exists": False,
    "fits_created_during_task": False,
    "fits_shape": [],
    "fits_max": 0.0,
    "fits_std": 0.0,
    "png_exists": False,
    "png_created_during_task": False,
    "png_size": [],
    "png_mean_brightness": 0.0
}

# 1. Analyze the FITS Output
if os.path.exists(fits_path):
    result["fits_exists"] = True
    mtime = os.path.getmtime(fits_path)
    if mtime >= start_time:
        result["fits_created_during_task"] = True
        
    try:
        from astropy.io import fits
        with fits.open(fits_path) as hdul:
            data = hdul[0].data
            if data is not None:
                result["fits_shape"] = list(data.shape)
                result["fits_max"] = float(np.max(data))
                result["fits_std"] = float(np.std(data))
    except Exception as e:
        print(f"Error reading FITS: {e}")

# 2. Analyze the PNG Output
if os.path.exists(png_path):
    result["png_exists"] = True
    mtime = os.path.getmtime(png_path)
    if mtime >= start_time:
        result["png_created_during_task"] = True
        
    try:
        import cv2
        # Read as grayscale to evaluate overall brightness (LUT inversion check)
        img = cv2.imread(png_path, cv2.IMREAD_GRAYSCALE)
        if img is not None:
            # cv2 shape is (height, width)
            result["png_size"] = [img.shape[1], img.shape[0]] 
            result["png_mean_brightness"] = float(np.mean(img))
    except Exception as e:
        print(f"Error reading PNG: {e}")

# Save JSON safely
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

# Execute analysis script
python3 /tmp/analyze_outputs.py "$TASK_START" "$TASK_END"

# Ensure permissive rights for the verifier to copy
chmod 666 /tmp/task_result.json

echo "Result Output:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="