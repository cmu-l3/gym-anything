#!/bin/bash
echo "=== Exporting pipeline_test_card_render result ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/test_card"
EXPECTED_FILE="$OUTPUT_DIR/testcard.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screen state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Find the output file
# Agent might name it slightly differently (e.g. testcard.0001.png) or use TGA
FOUND_FILE=""
if [ -f "$EXPECTED_FILE" ]; then
    FOUND_FILE="$EXPECTED_FILE"
else
    # Search for valid image files in the output dir created after task start
    # We look for png, tga, tif
    CANDIDATE=$(find "$OUTPUT_DIR" -type f \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) -printf "%T@ %p\n" | sort -n | tail -1 | awk '{print $2}')
    if [ -n "$CANDIDATE" ]; then
        FOUND_FILE="$CANDIDATE"
    fi
fi

# 3. Analyze file if found
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE_BYTES=0
IMAGE_WIDTH=0
IMAGE_HEIGHT=0
UNIQUE_COLORS=0
NON_BG_RATIO=0.0

if [ -n "$FOUND_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$FOUND_FILE" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$FOUND_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Analyze image content using Python
    # We check: Dimensions, Number of unique colors (is it blank?), 
    # and Ratio of non-background pixels (assuming top-left pixel is background)
    ANALYSIS=$(python3 -c "
import sys
from PIL import Image
import collections

try:
    img = Image.open('$FOUND_FILE').convert('RGB')
    width, height = img.size
    
    # Get all pixels
    pixels = list(img.getdata())
    total_pixels = len(pixels)
    
    # Count unique colors (optimization: stop if > 10 for performance, we just need to know if it's > 1)
    # Actually, for the ratio check, we need to iterate.
    # Let's assume top-left pixel is background color
    bg_color = pixels[0]
    non_bg_count = sum(1 for p in pixels if p != bg_color)
    
    # Unique colors (sample first 1000 pixels or full image if small)
    unique_colors = len(set(pixels[::10])) # subsample for speed
    
    ratio = float(non_bg_count) / float(total_pixels)
    
    print(f'{width} {height} {unique_colors} {ratio:.4f}')
except Exception as e:
    print('0 0 0 0.0')
")
    read -r IMAGE_WIDTH IMAGE_HEIGHT UNIQUE_COLORS NON_BG_RATIO <<< "$ANALYSIS"
fi

# 4. Generate JSON result
# Use temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "found_file_path": "$FOUND_FILE",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "unique_colors": $UNIQUE_COLORS,
    "non_bg_ratio": $NON_BG_RATIO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="