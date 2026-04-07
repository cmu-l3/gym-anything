#!/bin/bash
echo "=== Exporting Inverted Finding Chart Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use Python to analyze the output image securely inside the container
# This uses OpenCV to perform template matching against the original astronomical FITS data,
# proving the agent didn't just draw a fake white square.

cat > /tmp/analyze_chart.py << 'EOF'
import cv2
import numpy as np
import json
import os
import time
import sys

try:
    from astropy.io import fits
except ImportError:
    print("Astropy not found!")
    sys.exit(1)

OUTPUT_PATH = "/home/ga/AstroImages/finding_charts/output/m16_finding_chart.png"
FITS_PATH = "/home/ga/AstroImages/finding_charts/raw/656nmos.fits"

result = {
    "output_exists": False,
    "dimensions": [0, 0],
    "correlation_raw": 0.0,
    "correlation_inv": 0.0,
    "file_created_during_task": False,
    "error": None
}

try:
    with open("/tmp/task_start_time", "r") as f:
        start_time = int(f.read().strip())
except Exception:
    start_time = 0

if os.path.exists(OUTPUT_PATH):
    result["output_exists"] = True
    
    # Anti-gaming timestamp check
    if os.path.getmtime(OUTPUT_PATH) > start_time:
        result["file_created_during_task"] = True

    try:
        img_png = cv2.imread(OUTPUT_PATH, cv2.IMREAD_GRAYSCALE)
        if img_png is not None:
            h, w = img_png.shape
            result["dimensions"] = [int(w), int(h)]

            # Only attempt correlation if the image size is reasonable
            if 100 < w < 1000 and 100 < h < 1000:
                with fits.open(FITS_PATH) as hdul:
                    fits_data = hdul[0].data

                # Normalize raw FITS data for proper visual template matching
                fits_data = np.nan_to_num(fits_data, nan=np.nanmedian(fits_data))
                p1, p99 = np.percentile(fits_data, (1, 99.5))
                fits_norm = np.clip((fits_data - p1) / (p99 - p1), 0, 1)
                fits_8bit = (fits_norm * 255).astype(np.uint8)

                # Create the inverted version for the expected target
                fits_8bit_inv = 255 - fits_8bit

                # Define search window broadly around the requested crop coords (X=550, Y=550)
                # We extract a 700x700 search area to allow for slight cropping errors
                max_y, max_x = fits_8bit.shape
                y1, y2 = max(0, 450), min(max_y, 1150)
                x1, x2 = max(0, 450), min(max_x, 1150)

                search_raw = fits_8bit[y1:y2, x1:x2]
                search_inv = fits_8bit_inv[y1:y2, x1:x2]

                if h <= search_raw.shape[0] and w <= search_raw.shape[1]:
                    # Match against normal
                    res_raw = cv2.matchTemplate(search_raw, img_png, cv2.TM_CCOEFF_NORMED)
                    _, max_val_raw, _, _ = cv2.minMaxLoc(res_raw)
                    result["correlation_raw"] = float(max_val_raw)

                    # Match against inverted
                    res_inv = cv2.matchTemplate(search_inv, img_png, cv2.TM_CCOEFF_NORMED)
                    _, max_val_inv, _, _ = cv2.minMaxLoc(res_inv)
                    result["correlation_inv"] = float(max_val_inv)
                else:
                    result["error"] = "Agent's image is too large for the bounding box search window."
    except Exception as e:
        result["error"] = f"Image processing failed: {str(e)}"

# Write result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/analyze_chart.py

# Ensure permissions so the verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON exported."
cat /tmp/task_result.json
echo "=== Export complete ==="