#!/bin/bash
echo "=== Exporting circular_matte_composite result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/matte_test"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze output files using an internal Python script
# We run this INSIDE the container to avoid copying large numbers of images out.
# This script generates a JSON summary.

cat << 'EOF' > /tmp/analyze_matte.py
import os
import json
import sys
import glob
try:
    from PIL import Image, ImageChops
    import numpy as np
except ImportError:
    # Fallback if numpy not installed (though env spec says it is)
    sys.exit(0)

output_dir = sys.argv[1]
task_start = float(sys.argv[2])

results = {
    "frame_count": 0,
    "files_created_during_task": 0,
    "center_visible": False,
    "corners_transparent": False,
    "is_circular": False,
    "has_motion": False,
    "error": None
}

try:
    # Find PNG files
    files = sorted(glob.glob(os.path.join(output_dir, "*.png")))
    results["frame_count"] = len(files)
    
    if not files:
        print(json.dumps(results))
        sys.exit(0)

    # Check timestamps
    new_files = 0
    for f in files:
        if os.path.getmtime(f) > task_start:
            new_files += 1
    results["files_created_during_task"] = new_files

    # Analyze first frame for Matte properties
    first_img = Image.open(files[0]).convert("RGBA")
    width, height = first_img.size
    cx, cy = width // 2, height // 2
    
    # Get alpha channel
    alpha = np.array(first_img.split()[3])
    
    # 1. Check center visibility (should be opaque/visible)
    # We check a small region in the center
    center_region = alpha[cy-10:cy+10, cx-10:cx+10]
    avg_center = np.mean(center_region)
    results["center_visible"] = bool(avg_center > 0)
    
    # 2. Check corners (should be transparent)
    corners = [
        alpha[0:10, 0:10],          # Top-left
        alpha[0:10, width-10:width], # Top-right
        alpha[height-10:height, 0:10], # Bottom-left
        alpha[height-10:height, width-10:width] # Bottom-right
    ]
    avg_corners = np.mean([np.mean(c) for c in corners])
    results["corners_transparent"] = bool(avg_corners < 5) # Allow tiny anti-aliasing noise
    
    # 3. Check Circular Shape
    # Scan horizontal line from center to right edge
    # Expect transition from High Alpha -> Low Alpha
    mid_row = alpha[cy, cx:] # Center to right edge
    transition_point = -1
    
    # Find where alpha drops below threshold
    for x, val in enumerate(mid_row):
        if val < 10:
            transition_point = x
            break
            
    # Check vertical line (Center to bottom)
    mid_col = alpha[cy:, cx]
    v_transition_point = -1
    for y, val in enumerate(mid_col):
        if val < 10:
            v_transition_point = y
            break
            
    # If both transitions exist and are roughly equal, it's likely a circle/square
    # Real circle logic: check diagonal too
    if transition_point > 0 and v_transition_point > 0:
        ratio = transition_point / v_transition_point
        # Allow some aspect ratio difference if pixels aren't square, but generally expecting ~1.0
        results["is_circular"] = bool(0.8 < ratio < 1.2)

    # 4. Check Motion
    # Compare first frame center with last frame center
    if len(files) > 10:
        last_img = Image.open(files[-1]).convert("RGBA")
        
        # Calculate difference in RGB channels only (ignore alpha for motion check of character)
        diff = ImageChops.difference(first_img.convert("RGB"), last_img.convert("RGB"))
        
        # Only look at the center crop where the mask is open
        # We use the transition point radius estimated above, or default to 100px
        r = transition_point if transition_point > 0 else 100
        box = (cx-r, cy-r, cx+r, cy+r)
        
        # Ensure box is within bounds
        box = (max(0, box[0]), max(0, box[1]), min(width, box[2]), min(height, box[3]))
        
        diff_crop = diff.crop(box)
        stat = np.mean(np.array(diff_crop))
        
        results["has_motion"] = bool(stat > 1.0) # Any significant pixel change

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results))
EOF

# Run analysis
python3 /tmp/analyze_matte.py "$OUTPUT_DIR" "$TASK_START" > /tmp/analysis_result.json

# 3. Create final result JSON for export
RESULT_FILE="/tmp/task_result.json"
cat /tmp/analysis_result.json > "$RESULT_FILE"

# Clean up
rm -f /tmp/analyze_matte.py /tmp/analysis_result.json

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"