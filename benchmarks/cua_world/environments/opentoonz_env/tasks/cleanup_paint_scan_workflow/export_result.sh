#!/bin/bash
echo "=== Exporting Task Results ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/ink_and_paint"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Basic Stats
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
FILES_NEWER=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt | wc -l)

# 3. Perform Image Analysis (Inside Container)
# We use a python script to sample pixels from the rendered frames to verify:
# - Background color (should be Blue)
# - Circle fill color (should be Red)
# - Line presence (should be Dark)

cat > /tmp/analyze_frames.py << 'EOF'
import os
import glob
import json
import numpy as np
from PIL import Image

output_dir = "/home/ga/OpenToonz/output/ink_and_paint"
results = {
    "analyzed_frames": 0,
    "bg_color_match": False,
    "fill_color_match": False,
    "line_detected": False,
    "motion_detected": False,
    "avg_bg_color": [0, 0, 0],
    "avg_fill_color": [0, 0, 0]
}

try:
    files = sorted(glob.glob(os.path.join(output_dir, "*.png")))
    if not files:
        print(json.dumps(results))
        exit(0)

    results["analyzed_frames"] = len(files)
    
    bg_samples = []
    fill_samples = []
    centers_x = []

    # Analyze up to 5 frames
    for i, fpath in enumerate(files[:5]):
        try:
            img = Image.open(fpath).convert("RGB")
            arr = np.array(img)
            
            # 1. Sample Background (Top Left 50x50)
            # Expected: Blue (0, 0, 255)
            bg_patch = arr[0:50, 0:50]
            bg_avg = np.mean(bg_patch, axis=(0,1))
            bg_samples.append(bg_avg)
            
            # 2. Sample Fill (Center of expected circle position)
            # Setup logic: CX = 300 + (frame_idx * 40), CY = 500
            # Frame indices in glob might strictly follow 1..5, assume sorted
            # i=0 -> Frame 1 -> CX=340
            frame_idx = i + 1
            cx = 300 + (frame_idx * 40)
            cy = 500
            
            # Sample small patch at expected center
            fill_patch = arr[cy-10:cy+10, cx-10:cx+10]
            fill_avg = np.mean(fill_patch, axis=(0,1))
            fill_samples.append(fill_avg)
            
            # 3. Line Detection (Simple check for dark pixels)
            if np.any(arr < 50):
                results["line_detected"] = True

        except Exception as e:
            continue

    # Aggregating Results
    if bg_samples:
        avg_bg = np.mean(bg_samples, axis=0)
        results["avg_bg_color"] = avg_bg.tolist()
        # Check for Blue (Low R, Low G, High B)
        if avg_bg[2] > 150 and avg_bg[0] < 100 and avg_bg[1] < 100:
            results["bg_color_match"] = True

    if fill_samples:
        avg_fill = np.mean(fill_samples, axis=0)
        results["avg_fill_color"] = avg_fill.tolist()
        # Check for Red (High R, Low G, Low B)
        if avg_fill[0] > 150 and avg_fill[1] < 100 and avg_fill[2] < 100:
            results["fill_color_match"] = True
            
    # Check for color change in fill area across frames (Motion check)
    # If the circle moves, the pixel at (Frame1_Center) should change color in later frames
    if len(files) >= 2:
        img1 = np.array(Image.open(files[0]).convert("RGB"))
        img2 = np.array(Image.open(files[-1]).convert("RGB"))
        # Frame 1 center (340, 500) is Red in Frame 1.
        # In Frame 5, the circle has moved to 500. So (340, 500) should be Blue (Background).
        p1 = img1[500, 340]
        p2 = img2[500, 340]
        # Calculate distance between pixel colors
        dist = np.linalg.norm(p1 - p2)
        if dist > 50:
            results["motion_detected"] = True

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results))
EOF

# Run analysis
ANALYSIS_JSON=$(python3 /tmp/analyze_frames.py)

# 4. Construct Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_count": $FILE_COUNT,
    "files_created_during_task": $FILES_NEWER,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="