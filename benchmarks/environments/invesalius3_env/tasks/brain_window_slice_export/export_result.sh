#!/bin/bash
# Export result for brain_window_slice_export task

echo "=== Exporting brain_window_slice_export result ==="

source /workspace/scripts/task_utils.sh

# Paths
IMAGE_PATH="/home/ga/Documents/brain_window_slice.png"
INFO_PATH="/home/ga/Documents/slice_info.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot (evidence)
take_screenshot /tmp/task_final.png

# Analyze results using Python inside the container
# We verify file details and perform a histogram analysis to detect "Brain Window"
# Brain window (W~80, L~40) results in gray brain tissue (pixel values ~80-200).
# Bone window (W~2000, L~300) results in mostly black soft tissue and white bone.
python3 << PYEOF
import os
import json
import time

result = {
    "image_exists": False,
    "image_size": 0,
    "image_created_during_task": False,
    "info_exists": False,
    "slice_number": None,
    "gray_pixel_ratio": 0.0,  # Ratio of pixels in "brain gray" range
    "is_png": False
}

image_path = "$IMAGE_PATH"
info_path = "$INFO_PATH"
task_start = $TASK_START

# 1. Analyze Image File
if os.path.exists(image_path):
    result["image_exists"] = True
    result["image_size"] = os.path.getsize(image_path)
    
    # Check timestamp
    mtime = os.path.getmtime(image_path)
    if mtime > task_start:
        result["image_created_during_task"] = True

    # Check magic bytes for PNG
    try:
        with open(image_path, "rb") as f:
            header = f.read(8)
            if header == b"\x89PNG\r\n\x1a\n":
                result["is_png"] = True
    except:
        pass

    # Image Histogram Analysis (simple version without PIL/cv2 if missing)
    # Most InVesalius installs have PIL or numpy via dependencies, but let's be robust.
    # We'll try to use standard library or minimal imports if possible.
    try:
        from PIL import Image
        img = Image.open(image_path).convert('L') # Convert to grayscale
        hist = img.histogram()
        total_pixels = img.width * img.height
        
        # Count pixels in "brain gray" range (approx 80-200 out of 255)
        # Bone window: soft tissue is black (<50), bone is white (>230). Gap in middle.
        # Brain window: soft tissue is gray (80-200).
        gray_pixels = sum(hist[i] for i in range(70, 210))
        result["gray_pixel_ratio"] = float(gray_pixels) / float(total_pixels)
    except Exception as e:
        result["analysis_error"] = str(e)
        # Fallback: if we can't analyze histogram here, verifier.py might do VLM check

# 2. Analyze Text File
if os.path.exists(info_path):
    result["info_exists"] = True
    try:
        with open(info_path, 'r') as f:
            content = f.read().strip()
            # Try to find an integer
            import re
            match = re.search(r'\d+', content)
            if match:
                result["slice_number"] = int(match.group(0))
    except:
        pass

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="