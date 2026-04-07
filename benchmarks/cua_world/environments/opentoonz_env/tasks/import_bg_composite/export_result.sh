#!/bin/bash
echo "=== Exporting Import & Composite results ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/composite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Count Files
PNG_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
TOTAL_SIZE_BYTES=$(du -sb "$OUTPUT_DIR" 2>/dev/null | cut -f1 || echo "0")

# 2. Find first rendered frame
FIRST_FRAME=$(find "$OUTPUT_DIR" -name "*.png" | head -n 1)

# 3. Analyze content using Python
# We check:
# - File modification time (Anti-gaming)
# - Image Mode (RGBA/RGB)
# - Alpha channel status
# - Color distribution (Blue sky top, Green grass bottom)

cat << EOF > /tmp/analyze_frame.py
import sys
import json
import os
import time
from PIL import Image, ImageStat

result = {
    "files_valid_timestamp": False,
    "image_analyzed": False,
    "has_transparency": True,
    "top_blue_avg": 0,
    "bottom_green_avg": 0,
    "mode": "Unknown"
}

try:
    output_dir = "$OUTPUT_DIR"
    task_start = $TASK_START
    files = [os.path.join(output_dir, f) for f in os.listdir(output_dir) if f.endswith('.png')]
    
    if not files:
        print(json.dumps(result))
        sys.exit(0)

    # Check timestamps
    new_files = [f for f in files if os.path.getmtime(f) > task_start]
    if len(new_files) == len(files) and len(files) > 0:
        result["files_valid_timestamp"] = True

    # Analyze first image
    img_path = sorted(files)[0]
    img = Image.open(img_path).convert('RGBA')
    result["image_analyzed"] = True
    result["mode"] = img.mode
    
    width, height = img.size
    
    # Check Transparency (Alpha channel)
    # If background is composite, alpha should be 255 (opaque) everywhere
    # If background is missing, alpha will be 0 in empty areas
    extrema = img.getextrema()
    alpha_extrema = extrema[3] # (min, max) for alpha
    
    # If min alpha is 255, image is fully opaque (Good!)
    # If min alpha < 255, there are transparent pixels (Bad - background doesn't fill frame)
    if alpha_extrema[0] == 255:
        result["has_transparency"] = False
    else:
        result["has_transparency"] = True

    # Check Colors
    # Top 20% - Should be Sky Blue (High Blue channel)
    top_crop = img.crop((0, 0, width, int(height * 0.2)))
    top_stat = ImageStat.Stat(top_crop)
    result["top_blue_avg"] = top_stat.mean[2] # R=0, G=1, B=2

    # Bottom 20% - Should be Green Grass (High Green channel, low Blue)
    bottom_crop = img.crop((0, int(height * 0.8), width, height))
    bottom_stat = ImageStat.Stat(bottom_crop)
    result["bottom_green_avg"] = bottom_stat.mean[1]

    print(json.dumps(result))

except Exception as e:
    result["error"] = str(e)
    print(json.dumps(result))
EOF

ANALYSIS=$(python3 /tmp/analyze_frame.py)

# 4. Construct Final JSON
cat << EOF > "$RESULT_JSON"
{
    "task_start": $TASK_START,
    "file_count": $PNG_COUNT,
    "total_size_bytes": $TOTAL_SIZE_BYTES,
    "analysis": $ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Analysis complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"