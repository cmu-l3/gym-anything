#!/bin/bash
# Export script for accessible_figure_creation task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Accessible Figure Result ==="

take_screenshot /tmp/task_end_screenshot.png 2>/dev/null

# Python script to analyze the image content
python3 << 'PYEOF'
import json
import os
import sys
import numpy as np
from PIL import Image

output_file = "/home/ga/ImageJ_Data/results/accessible_figure.png"
task_start_file = "/tmp/task_start_timestamp"

result = {
    "file_exists": False,
    "file_valid": False,
    "width": 0,
    "height": 0,
    "red_pixel_ratio": 0.0,
    "magenta_pixel_ratio": 0.0,
    "green_pixel_ratio": 0.0,
    "scale_bar_detected": False,
    "scale_bar_pixels": 0,
    "timestamp_valid": False
}

# Check timestamp
try:
    if os.path.exists(output_file) and os.path.exists(task_start_file):
        start_time = int(open(task_start_file).read().strip())
        mod_time = int(os.path.getmtime(output_file))
        if mod_time > start_time:
            result["timestamp_valid"] = True
except Exception as e:
    print(f"Timestamp check error: {e}")

if os.path.exists(output_file):
    result["file_exists"] = True
    try:
        img = Image.open(output_file).convert('RGB')
        result["file_valid"] = True
        result["width"], result["height"] = img.size
        
        # Convert to numpy for fast pixel analysis
        data = np.array(img)
        
        # Total pixels
        total_pixels = data.shape[0] * data.shape[1]
        
        # Color Analysis
        # R, G, B channels
        R = data[:,:,0].astype(int)
        G = data[:,:,1].astype(int)
        B = data[:,:,2].astype(int)
        
        # Threshold for "on" pixels
        thresh = 100
        low_thresh = 50
        
        # 1. Pure Red Pixels (Bad): High Red, Low Green, Low Blue
        # Should be minimal if converted to Magenta
        red_mask = (R > thresh) & (G < low_thresh) & (B < low_thresh)
        result["red_pixel_ratio"] = np.sum(red_mask) / total_pixels
        
        # 2. Magenta Pixels (Good): High Red AND High Blue
        # This indicates Channel 1 was remapped
        magenta_mask = (R > thresh) & (B > thresh) & (G < 200) # G<200 avoids white
        result["magenta_pixel_ratio"] = np.sum(magenta_mask) / total_pixels
        
        # 3. Green Pixels (Good): High Green, Low Red/Blue
        green_mask = (G > thresh) & (R < 200) & (B < 200)
        result["green_pixel_ratio"] = np.sum(green_mask) / total_pixels
        
        # Scale Bar Analysis
        # Scale bar should be pure white (255, 255, 255) in the lower right
        # Crop bottom-right 25% of image
        h, w = data.shape[:2]
        crop_y = int(h * 0.75)
        crop_x = int(w * 0.75)
        
        br_quadrant = data[crop_y:, crop_x:, :]
        
        # Look for pure white pixels
        # Allow slight compression artifacts (e.g. > 250)
        white_thresh = 250
        white_mask = (br_quadrant[:,:,0] > white_thresh) & \
                     (br_quadrant[:,:,1] > white_thresh) & \
                     (br_quadrant[:,:,2] > white_thresh)
        
        white_pixels = np.sum(white_mask)
        result["scale_bar_pixels"] = int(white_pixels)
        
        # A 10 micron scale bar at 0.16 um/px is ~62 pixels wide
        # Height usually ~5-10 pixels. Area ~300-600 pixels + text.
        # Minimal threshold to detect *something* added
        if white_pixels > 50: 
            result["scale_bar_detected"] = True
            
    except Exception as e:
        print(f"Image analysis error: {e}")

# Save result
with open("/tmp/accessible_figure_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="