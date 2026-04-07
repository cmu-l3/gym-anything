#!/bin/bash
echo "=== Exporting character_fade_out_fx results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/OpenToonz/output/fade_out"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Python script to analyze rendered frames
# We need to check:
# 1. Are files created after task start?
# 2. Do they have alpha channel?
# 3. Does Frame 1 have high alpha?
# 4. Does Frame 20 have low alpha?
# 5. Is there a gradient in between?

cat << 'EOF' > /tmp/analyze_render.py
import os
import sys
import json
import glob
from PIL import Image
import numpy as np

output_dir = sys.argv[1]
task_start = float(sys.argv[2])

result = {
    "file_count": 0,
    "files_valid_time": False,
    "frame_data": {},
    "error": None
}

try:
    # Find PNG files
    files = sorted(glob.glob(os.path.join(output_dir, "*.png")))
    result["file_count"] = len(files)

    if len(files) == 0:
        print(json.dumps(result))
        sys.exit(0)

    # Check timestamps
    new_files = 0
    for f in files:
        if os.path.getmtime(f) > task_start:
            new_files += 1
    
    if new_files >= len(files) * 0.9 and len(files) > 0:
        result["files_valid_time"] = True

    # Analyze specific frames if they exist
    # We expect frames usually named name.0001.png or similar. 
    # Since we sorted, we can likely grab by index, but let's be careful.
    
    # Map indices 0 (start), 4 (25%), 9 (50%), 14 (75%), 19 (end) 
    # corresponding to frames 1, 5, 10, 15, 20
    check_indices = {
        1: 0, 
        5: 4, 
        10: 9, 
        15: 14, 
        20: 19
    }

    for frame_num, idx in check_indices.items():
        if idx < len(files):
            file_path = files[idx]
            try:
                img = Image.open(file_path).convert("RGBA")
                alpha = np.array(img.split()[-1])
                
                # Calculate statistics for alpha channel
                # We care about the max alpha (is anything visible?)
                # And mean alpha of non-transparent pixels (how visible is it?)
                
                max_alpha = float(np.max(alpha))
                mean_alpha = float(np.mean(alpha))
                
                # Check center region where character usually is to avoid edge artifacts
                w, h = img.size
                center_crop = alpha[h//4:3*h//4, w//4:3*w//4]
                center_max = float(np.max(center_crop)) if center_crop.size > 0 else 0
                
                result["frame_data"][str(frame_num)] = {
                    "max_alpha": max_alpha,
                    "mean_alpha": mean_alpha,
                    "center_max_alpha": center_max,
                    "path": os.path.basename(file_path)
                }
            except Exception as e:
                print(f"Error processing frame {frame_num}: {e}", file=sys.stderr)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run analysis
if [ -d "$OUTPUT_DIR" ]; then
    python3 /tmp/analyze_render.py "$OUTPUT_DIR" "$TASK_START" > /tmp/task_result.json
else
    echo '{"file_count": 0, "error": "Output directory not found"}' > /tmp/task_result.json
fi

# Set permissions
chmod 666 /tmp/task_result.json
echo "Analysis complete. Result:"
cat /tmp/task_result.json

echo "=== Export complete ==="