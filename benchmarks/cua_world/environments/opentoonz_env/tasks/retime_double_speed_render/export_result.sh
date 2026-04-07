#!/bin/bash
echo "=== Exporting retime_double_speed_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/double_speed"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
ORIGINAL_FRAME_COUNT=$(cat /tmp/original_frame_count.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Count output frames
# Look for image sequences (png, tga, tif, jpg)
OUTPUT_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" -o -name "*.jpg" \) -type f 2>/dev/null | wc -l)

# 3. Check timestamps (Anti-gaming)
# Count how many files were modified AFTER the task started
NEW_FILES_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" -o -name "*.jpg" \) -newer /tmp/task_start_timestamp -type f 2>/dev/null | wc -l)

# 4. Measure directory size
TOTAL_SIZE_BYTES=$(du -sb "$OUTPUT_DIR" 2>/dev/null | cut -f1)
TOTAL_SIZE_BYTES=${TOTAL_SIZE_BYTES:-0}

# 5. Get Image Dimensions (of the first found image)
FIRST_IMG=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" -o -name "*.jpg" \) -type f 2>/dev/null | head -1)
IMG_WIDTH=0
IMG_HEIGHT=0

if [ -n "$FIRST_IMG" ]; then
    DIMS=$(python3 -c "
import sys
try:
    from PIL import Image
    img = Image.open('$FIRST_IMG')
    print(f'{img.width} {img.height}')
except:
    print('0 0')
")
    IMG_WIDTH=$(echo "$DIMS" | cut -d' ' -f1)
    IMG_HEIGHT=$(echo "$DIMS" | cut -d' ' -f2)
fi

# 6. Check if OpenToonz is still running
APP_RUNNING="false"
if pgrep -f "opentoonz" > /dev/null; then
    APP_RUNNING="true"
fi

# 7. Create JSON result
RESULT_FILE="/tmp/task_result.json"
cat > "$RESULT_FILE" << EOF
{
    "original_frame_count": $ORIGINAL_FRAME_COUNT,
    "output_frame_count": $OUTPUT_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "total_size_bytes": $TOTAL_SIZE_BYTES,
    "img_width": $IMG_WIDTH,
    "img_height": $IMG_HEIGHT,
    "app_running": $APP_RUNNING,
    "output_dir": "$OUTPUT_DIR",
    "task_start_timestamp": $TASK_START
}
EOF

# Ensure readable
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="