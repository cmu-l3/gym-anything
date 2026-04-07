#!/bin/bash
echo "=== Exporting Cross Dissolve Results ==="

ASSETS_DIR="/home/ga/OpenToonz/assets"
OUTPUT_DIR="/home/ga/OpenToonz/output/dissolve"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Basic File Checks
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
echo "Found $FILE_COUNT frames in output directory."

# Check if files were actually created during task
NEW_FILES=$(find "$OUTPUT_DIR" -name "*.png" -newermt "@$TASK_START" | wc -l)
echo "Found $NEW_FILES new frames created during task."

# 2. Pixel-Level Verification (Python Script)
# We run this INSIDE the container to access the generated images directly.
# This script calculates Mean Squared Error (MSE) against expected blends.

cat > /tmp/analyze_dissolve.py << 'EOF'
import os
import sys
import json
import numpy as np
from PIL import Image

def load_image(path, target_size=None):
    try:
        img = Image.open(path).convert('RGB')
        if target_size:
            img = img.resize(target_size)
        return np.array(img, dtype=np.float32)
    except Exception as e:
        print(f"Error loading {path}: {e}", file=sys.stderr)
        return None

def mse(img1, img2):
    return np.mean((img1 - img2) ** 2)

assets_dir = "/home/ga/OpenToonz/assets"
output_dir = "/home/ga/OpenToonz/output/dissolve"
results = {
    "start_mse": 9999,
    "end_mse": 9999,
    "mid_mse": 9999,
    "monotonicity_score": 0,
    "frame_count": 0,
    "resolution_match": False,
    "error": None
}

try:
    # Get sorted frame list
    frames = sorted([f for f in os.listdir(output_dir) if f.endswith('.png')])
    results["frame_count"] = len(frames)

    if len(frames) >= 24:
        # Load Sources
        day_img = load_image(os.path.join(assets_dir, "day_bg.png"))
        night_img = load_image(os.path.join(assets_dir, "night_bg.png"))
        
        # Determine target resolution from source
        h, w, c = day_img.shape

        # Load Key Output Frames (1, 12, 24)
        # Note: OpenToonz might name them name.0001.png or name0001.png
        # We rely on sorted list index.
        frame_start = load_image(os.path.join(output_dir, frames[0]), (w, h))
        frame_mid   = load_image(os.path.join(output_dir, frames[11]), (w, h)) # Frame 12 (index 11)
        frame_end   = load_image(os.path.join(output_dir, frames[23]), (w, h)) # Frame 24 (index 23)

        if frame_start is not None and frame_end is not None:
            # Check Resolution
            if frame_start.shape == day_img.shape:
                results["resolution_match"] = True

            # 1. Endpoint Checks
            results["start_mse"] = float(mse(frame_start, day_img))
            results["end_mse"]   = float(mse(frame_end, night_img))

            # 2. Midpoint Check (Should be 50/50 blend)
            expected_mid = (day_img * 0.5) + (night_img * 0.5)
            results["mid_mse"] = float(mse(frame_mid, expected_mid))

            # 3. Monotonicity / Smoothness Check
            # We check if the transition is roughly linear.
            # Sample a 50x50 patch from center to speed up
            cy, cx = h//2, w//2
            patch_day = day_img[cy:cy+50, cx:cx+50]
            patch_night = night_img[cy:cy+50, cx:cx+50]
            
            # If day and night are too similar in this patch, this check is invalid, but landscapes usually differ.
            diff_patch = np.abs(patch_day - patch_night).mean()
            
            if diff_patch > 10:
                # Check indices 0, 5, 11, 17, 23
                indices = [0, 5, 11, 17, 23]
                progressions = []
                for i in indices:
                    f_path = os.path.join(output_dir, frames[i])
                    f_img = load_image(f_path, (w, h))
                    if f_img is None: continue
                    f_patch = f_img[cy:cy+50, cx:cx+50]
                    
                    # Calculate distance from Day
                    dist = np.mean(np.abs(f_patch - patch_day))
                    progressions.append(dist)
                
                # Check if distance from Day increases monotonically
                is_monotonic = all(x <= y for x, y in zip(progressions, progressions[1:]))
                results["monotonicity_score"] = 1.0 if is_monotonic else 0.0
                results["progression_vals"] = [float(x) for x in progressions]
            else:
                results["monotonicity_score"] = 1.0 # Skip check if source patches identical
                results["check_skipped"] = "low_contrast_patch"

except Exception as e:
    results["error"] = str(e)
    import traceback
    traceback.print_exc()

print(json.dumps(results))
EOF

# Run analysis
echo "Running pixel analysis..."
ANALYSIS_JSON=$(python3 /tmp/analyze_dissolve.py)
echo "Analysis complete."

# Construct Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_count": $FILE_COUNT,
    "new_files_count": $NEW_FILES,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="