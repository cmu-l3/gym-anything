#!/bin/bash
# Export script for ml_image_preprocessing task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting ML Preprocessing Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Define paths
RESULT_FILE="/home/ga/ImageJ_Data/processed/blobs_ml_ready.tif"
TASK_START_FILE="/tmp/task_start_timestamp"
JSON_OUTPUT="/tmp/ml_preprocessing_result.json"

# Use Python to inspect the output image file directly
# This gathers metadata for the verifier to score
python3 << PYEOF
import json
import os
import sys
import numpy as np
from PIL import Image

output = {
    "file_exists": False,
    "file_size_bytes": 0,
    "width": 0,
    "height": 0,
    "mode": "unknown",
    "format": "unknown",
    "padding_is_black": False,
    "center_has_content": False,
    "is_inverted": False,
    "task_start_timestamp": 0,
    "file_modified_time": 0,
    "error": None
}

try:
    # Read task start time
    if os.path.exists("$TASK_START_FILE"):
        with open("$TASK_START_FILE", 'r') as f:
            output["task_start_timestamp"] = int(f.read().strip())

    result_path = "$RESULT_FILE"
    
    if os.path.exists(result_path):
        output["file_exists"] = True
        output["file_size_bytes"] = os.path.getsize(result_path)
        output["file_modified_time"] = int(os.path.getmtime(result_path))
        
        try:
            img = Image.open(result_path)
            output["width"], output["height"] = img.size
            output["mode"] = img.mode
            output["format"] = img.format
            
            # Convert to numpy for analysis
            data = np.array(img)
            
            # 1. Check Padding (first 5 pixels on borders)
            # Top 10 rows, Bottom 10 rows, Left 10 cols, Right 10 cols
            top_border = data[:10, :]
            bottom_border = data[-10:, :]
            left_border = data[:, :10]
            right_border = data[:, -10:]
            
            borders = np.concatenate([
                top_border.flatten(), 
                bottom_border.flatten(),
                left_border.flatten(),
                right_border.flatten()
            ])
            
            # Check if borders are largely black (allow small noise/compression artifacts < 5)
            # In an inverted image standardized to black background, padding should be 0.
            mean_border = np.mean(borders)
            output["padding_mean"] = float(mean_border)
            output["padding_is_black"] = mean_border < 5.0
            
            # 2. Check Center Content (Inversion check)
            # The original blobs are dark on light. Inverted blobs are bright on dark.
            # Center 50x50 region should contain the image content.
            # If inverted properly, background of the image content should be dark, 
            # matching the padding, and blobs should be bright.
            
            h, w = data.shape[:2]
            cy, cx = h//2, w//2
            center_region = data[cy-50:cy+50, cx-50:cx+50]
            
            output["center_mean"] = float(np.mean(center_region))
            output["center_std"] = float(np.std(center_region))
            
            # Content check: Standard deviation should be high if image is there
            output["center_has_content"] = output["center_std"] > 10.0
            
            # Inversion check: 
            # Original Blobs background is ~240 (white). Inverted background is ~15 (black).
            # Blobs themselves are ~50 (dark). Inverted blobs are ~200 (bright).
            # If inverted, max pixel in center should be high (>150)
            output["center_max"] = float(np.max(center_region))
            output["is_inverted"] = output["center_max"] > 128
            
        except Exception as e:
            output["error"] = f"Image analysis error: {str(e)}"
            
except Exception as e:
    output["error"] = str(e)

with open("$JSON_OUTPUT", 'w') as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
PYEOF

echo "=== Export Complete ==="