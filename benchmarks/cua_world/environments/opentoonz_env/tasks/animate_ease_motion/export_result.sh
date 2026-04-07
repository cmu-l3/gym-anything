#!/bin/bash
echo "=== Exporting animate_ease_motion result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/ease_test"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Basic File Checks
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" 2>/dev/null | wc -l)
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)
APP_RUNNING=$(pgrep -f "OpenToonz" > /dev/null && echo "true" || echo "false")

# 3. Analyze Motion Profile inside the container
# We use a python script here to calculate centroids and verify the "Ease" curve
# This avoids transferring 24+ images to the host, we just transfer the metrics.

cat << 'EOF' > /tmp/analyze_motion.py
import os
import glob
import json
import sys
import numpy as np
from PIL import Image

output_dir = "/home/ga/OpenToonz/output/ease_test"
frames = sorted(glob.glob(os.path.join(output_dir, "*.png")))

results = {
    "frame_count": len(frames),
    "centroids_x": [],
    "centroids_y": [],
    "asset_detected": False,
    "error": None
}

if not frames:
    print(json.dumps(results))
    sys.exit(0)

try:
    centroids_x = []
    centroids_y = []
    
    # Check middle frame for content (Asset Usage check)
    mid_idx = len(frames) // 2
    if mid_idx < len(frames):
        mid_img = Image.open(frames[mid_idx]).convert('RGBA')
        mid_arr = np.array(mid_img)
        if np.sum(mid_arr[:,:,3]) > 1000: # Check alpha channel sum
            results["asset_detected"] = True

    # Calculate centroids for all frames
    for f in frames:
        try:
            img = Image.open(f).convert('RGBA')
            arr = np.array(img)
            # Find pixels with alpha > 10
            y_idxs, x_idxs = np.nonzero(arr[:, :, 3] > 10)
            
            if len(x_idxs) > 0:
                cx = float(np.mean(x_idxs))
                cy = float(np.mean(y_idxs))
                centroids_x.append(cx)
                centroids_y.append(cy)
            else:
                # Empty frame, preserve index with None or last known
                centroids_x.append(-1.0) 
                centroids_y.append(-1.0)
        except Exception as e:
            centroids_x.append(-1.0)
            centroids_y.append(-1.0)

    results["centroids_x"] = centroids_x
    results["centroids_y"] = centroids_y

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results))
EOF

# Run the analysis script
ANALYSIS_JSON=$(python3 /tmp/analyze_motion.py)

# 4. Construct Final JSON
# We embed the analysis results directly into the export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_count": $FILE_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "app_running": $APP_RUNNING,
    "motion_analysis": $ANALYSIS_JSON
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="