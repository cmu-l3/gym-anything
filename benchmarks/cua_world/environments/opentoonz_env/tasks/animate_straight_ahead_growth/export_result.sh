#!/bin/bash
echo "=== Exporting animate_straight_ahead_growth result ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/growth_anim"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 1. Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to analyze the rendered images
# This script calculates pixel area for each frame to verify "growth"
cat << 'EOF' > /tmp/analyze_growth.py
import os
import json
import sys
from PIL import Image

output_dir = sys.argv[1]
task_start_time = float(sys.argv[2])

results = {
    "frame_count": 0,
    "frames_created_during_task": 0,
    "has_transparency": False,
    "growth_data": [],
    "file_list": []
}

if not os.path.exists(output_dir):
    print(json.dumps(results))
    sys.exit(0)

# Get list of PNG files
files = sorted([f for f in os.listdir(output_dir) if f.lower().endswith('.png')])
results["frame_count"] = len(files)
results["file_list"] = files

growth_areas = []
valid_timestamps = 0
transparent_frames = 0

for filename in files:
    filepath = os.path.join(output_dir, filename)
    
    # Check timestamp
    mtime = os.path.getmtime(filepath)
    if mtime > task_start_time:
        valid_timestamps += 1
        
    try:
        with Image.open(filepath) as img:
            # Check transparency (Alpha channel)
            if img.mode == 'RGBA':
                # Get alpha channel data
                alpha = img.split()[-1]
                # Count non-transparent pixels (threshold > 0)
                # This is a rough "content area" calculation
                non_zero_pixels = 0
                data = alpha.getdata()
                for pixel in data:
                    if pixel > 0:
                        non_zero_pixels += 1
                
                growth_areas.append(non_zero_pixels)
                
                # Check if image is not fully opaque rectangle (has some transparent pixels)
                # If non_zero_pixels is significantly less than total pixels
                total_pixels = img.width * img.height
                if non_zero_pixels < total_pixels:
                    transparent_frames += 1
            else:
                # Fallback for RGB images (no alpha) - treat as full area if content detection fails
                # But task requires transparency
                growth_areas.append(0) 
                
    except Exception as e:
        # Corrupt file or read error
        growth_areas.append(0)

results["frames_created_during_task"] = valid_timestamps
results["growth_data"] = growth_areas
results["has_transparency"] = (transparent_frames > 0)

print(json.dumps(results))
EOF

# 3. Run analysis
echo "Running image analysis..."
if [ -d "$OUTPUT_DIR" ]; then
    python3 /tmp/analyze_growth.py "$OUTPUT_DIR" "$TASK_START" > "$RESULT_JSON"
else
    # Output dir missing
    echo '{"frame_count": 0, "error": "Output directory not found"}' > "$RESULT_JSON"
fi

# 4. Add screenshot path to JSON
# We use a temp file to merge because we don't have 'jq' guaranteed
TEMP_MERGE=$(mktemp)
cat "$RESULT_JSON" | python3 -c "import sys, json; data = json.load(sys.stdin); data['screenshot_path'] = '/tmp/task_final.png'; print(json.dumps(data))" > "$TEMP_MERGE"
mv "$TEMP_MERGE" "$RESULT_JSON"

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Analysis complete. Result:"
cat "$RESULT_JSON"
echo "=== Export complete ==="