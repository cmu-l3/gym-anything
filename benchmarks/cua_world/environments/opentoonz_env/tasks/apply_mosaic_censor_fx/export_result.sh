#!/bin/bash
echo "=== Exporting apply_mosaic_censor_fx results ==="

# Configuration
OUTPUT_DIR="/home/ga/OpenToonz/output/mosaic_censor"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"

# 1. Capture Final Screenshot (Evidence of UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python Script for Image Analysis
# We run this INSIDE the container to analyze the rendered frames against requirements.
# It calculates:
# - Frame count
# - Timestamp validity
# - Visual Difference (vs original clean render, implicit comparison if original not available)
# - "Blockiness" (Mosaic Signature)

cat << 'EOF' > /tmp/analyze_results.py
import os
import sys
import json
import glob
import time
import numpy as np
from PIL import Image

output_dir = sys.argv[1]
task_start = float(sys.argv[2])

results = {
    "files_found": 0,
    "files_valid_time": 0,
    "avg_blockiness": 0.0,
    "has_content": False,
    "image_path": ""
}

try:
    # Find PNG files
    files = sorted(glob.glob(os.path.join(output_dir, "*.png")))
    results["files_found"] = len(files)

    valid_time_count = 0
    total_blockiness = 0
    checked_files = 0
    
    first_image_path = ""

    for f in files:
        # Check timestamp
        mtime = os.path.getmtime(f)
        if mtime > task_start:
            valid_time_count += 1

        # Analyze content (sample first 3 frames to save time)
        if checked_files < 3:
            try:
                img = Image.open(f).convert('RGB')
                arr = np.array(img)
                
                if checked_files == 0:
                    first_image_path = f
                    # Check if empty/black/white
                    if np.std(arr) > 5: # Threshold for "not solid color"
                        results["has_content"] = True

                # --- Blockiness Metric ---
                # A mosaic effect creates constant color blocks.
                # We check horizontal pixel differences. In a mosaic, many neighbors are identical.
                # Calculate % of pixels that are identical to their right-neighbor.
                # Standard photo ~5-10%. Mosaic ~80-90% (depends on block size).
                
                # Convert to grayscale for simpler gradient calc
                gray = np.mean(arr, axis=2)
                
                # Diff with right neighbor
                diff_x = np.abs(gray[:, :-1] - gray[:, 1:])
                
                # Count zero diffs (tolerance < 2 for compression artifacts)
                flat_pixels = np.sum(diff_x < 2)
                total_pixels = diff_x.size
                
                blockiness = flat_pixels / total_pixels
                total_blockiness += blockiness
                checked_files += 1
                
            except Exception as e:
                print(f"Error analyzing image {f}: {e}")

    results["files_valid_time"] = valid_time_count
    if checked_files > 0:
        results["avg_blockiness"] = total_blockiness / checked_files
    if first_image_path:
        results["image_path"] = first_image_path

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results))
EOF

# Run analysis
echo "Running image analysis..."
ANALYSIS_JSON=$(python3 /tmp/analyze_results.py "$OUTPUT_DIR" "$TASK_START")
echo "Analysis result: $ANALYSIS_JSON"

# 3. Check Scene File Modification (Secondary signal)
# Did the agent actually save the scene? Not strictly required if they rendered, but good signal.
SCENE_MODIFIED="false"
if [ -f "$SCENE_PATH" ]; then
    SCENE_MTIME=$(stat -c %Y "$SCENE_PATH")
    if [ "$SCENE_MTIME" -gt "$TASK_START" ]; then
        SCENE_MODIFIED="true"
    fi
fi

# 4. Construct Final JSON
# We embed the Python analysis results into the final JSON
cat << EOF > /tmp/task_result.json
{
    "analysis": $ANALYSIS_JSON,
    "scene_modified": $SCENE_MODIFIED,
    "final_screenshot": "/tmp/task_final.png"
}
EOF

# 5. Handle Permissions (so host can read)
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png

echo "=== Export complete ==="