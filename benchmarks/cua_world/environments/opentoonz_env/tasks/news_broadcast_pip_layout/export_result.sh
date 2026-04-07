#!/bin/bash
echo "=== Exporting news_broadcast_pip_layout results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/OpenToonz/output/news_pip"
BG_IMAGE="/home/ga/Documents/TaskData/city_background.jpg"
JSON_OUTPUT="/tmp/task_result.json"

# Python script to analyze the images
python3 - <<EOF
import os
import json
import glob
from PIL import Image
import numpy as np

output_dir = "$OUTPUT_DIR"
bg_image_path = "$BG_IMAGE"
task_start = $TASK_START
result = {
    "frame_count": 0,
    "valid_resolution_count": 0,
    "files_created_during_task": False,
    "bl_quadrant_match": 0.0,
    "tr_quadrant_activity": 0.0,
    "tr_motion_score": 0.0,
    "resolution": [0, 0]
}

try:
    # Get list of PNG files
    files = sorted(glob.glob(os.path.join(output_dir, "*.png")))
    result["frame_count"] = len(files)
    
    if len(files) > 0:
        # Check timestamps
        new_files = [f for f in files if os.path.getmtime(f) > task_start]
        result["files_created_during_task"] = len(new_files) > 0
        
        # Analyze first valid frame
        first_frame_path = files[0]
        img = Image.open(first_frame_path).convert('RGB')
        result["resolution"] = list(img.size)
        
        if img.size == (1920, 1080):
            result["valid_resolution_count"] = sum(1 for f in files if Image.open(f).size == (1920, 1080))
            
            # Load Background
            if os.path.exists(bg_image_path):
                bg_img = Image.open(bg_image_path).convert('RGB')
                bg_img = bg_img.resize((1920, 1080))
                
                # Define Quadrants (0,0 is top-left)
                # TR: x > 960, y < 540
                # BL: x < 960, y > 540
                
                # Convert to numpy
                img_arr = np.array(img)
                bg_arr = np.array(bg_img)
                
                # 1. Check BL Quadrant (Background Visibility)
                # Slice: rows 540:1080, cols 0:960
                bl_slice_img = img_arr[540:, :960]
                bl_slice_bg = bg_arr[540:, :960]
                
                # Calculate similarity (normalized inverse difference)
                diff_bl = np.mean(np.abs(bl_slice_img - bl_slice_bg))
                # diff_bl is avg pixel diff (0-255). 0 is perfect match.
                # Score 0-1, where 0 diff = 1.0 score
                result["bl_quadrant_match"] = max(0, 1.0 - (diff_bl / 50.0)) 
                
                # 2. Check TR Quadrant (Animation Presence)
                # Slice: rows 0:540, cols 960:1920
                tr_slice_img = img_arr[:540, 960:]
                tr_slice_bg = bg_arr[:540, 960:]
                
                # Calculate difference from background (Activity)
                # We EXPECT difference here (character overlay)
                diff_tr = np.mean(np.abs(tr_slice_img - tr_slice_bg))
                result["tr_quadrant_activity"] = min(1.0, diff_tr / 10.0)
                
                # 3. Check Motion in TR Quadrant
                # Compare frame 0 and frame 5 (or last)
                if len(files) > 5:
                    img_last = Image.open(files[5]).convert('RGB')
                    if img_last.size == (1920, 1080):
                        tr_slice_last = np.array(img_last)[:540, 960:]
                        diff_motion = np.mean(np.abs(tr_slice_img - tr_slice_last))
                        result["tr_motion_score"] = min(1.0, diff_motion / 5.0)

except Exception as e:
    result["error"] = str(e)

with open("$JSON_OUTPUT", "w") as f:
    json.dump(result, f)
EOF

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Set permissions
chmod 666 "$JSON_OUTPUT" 2>/dev/null || true

echo "=== Export complete ==="
cat "$JSON_OUTPUT"