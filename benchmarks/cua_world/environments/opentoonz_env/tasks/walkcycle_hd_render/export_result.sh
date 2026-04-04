#!/bin/bash
echo "=== Exporting walkcycle_hd_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/walkcycle_hd"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Count image files in output dir (PNG and TGA are both valid render outputs)
PNG_COUNT=$(find "$OUTPUT_DIR" -maxdepth 2 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | wc -l)
PNG_COUNT=${PNG_COUNT:-0}

# Get dimensions of first image using Python/PIL
FIRST_IMG=$(find "$OUTPUT_DIR" -maxdepth 2 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | sort | head -1)
IMG_WIDTH=0
IMG_HEIGHT=0

if [ -n "$FIRST_IMG" ]; then
    DIMS=$(python3 -c "
from PIL import Image
import sys
try:
    img = Image.open('$FIRST_IMG')
    print(img.width, img.height)
except Exception as e:
    print('0 0')
" 2>/dev/null || echo "0 0")
    IMG_WIDTH=$(echo "$DIMS" | awk '{print $1}')
    IMG_HEIGHT=$(echo "$DIMS" | awk '{print $2}')
fi

# Count files created after task start
FILES_AFTER_START=$(find "$OUTPUT_DIR" -maxdepth 2 \( -name "*.png" -o -name "*.tga" \) -newer /tmp/task_start_timestamp -type f 2>/dev/null | wc -l)
FILES_AFTER_START=${FILES_AFTER_START:-0}

# Measure total output directory size in KB
TOTAL_SIZE_KB=0
if [ -d "$OUTPUT_DIR" ]; then
    TOTAL_SIZE_KB=$(du -sk "$OUTPUT_DIR" 2>/dev/null | awk '{print $1}')
fi
TOTAL_SIZE_KB=${TOTAL_SIZE_KB:-0}

# Get baseline count
INITIAL_COUNT=$(cat /tmp/walkcycle_hd_initial_count 2>/dev/null || echo "0")

# Write result JSON
RESULT_FILE="/tmp/walkcycle_hd_result.json"
cat > "$RESULT_FILE" << RESULTEOF
{
    "png_count": $PNG_COUNT,
    "img_width": $IMG_WIDTH,
    "img_height": $IMG_HEIGHT,
    "files_after_start": $FILES_AFTER_START,
    "total_size_kb": $TOTAL_SIZE_KB,
    "initial_count": $INITIAL_COUNT,
    "output_dir": "$OUTPUT_DIR",
    "task_start": $TASK_START
}
RESULTEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="
