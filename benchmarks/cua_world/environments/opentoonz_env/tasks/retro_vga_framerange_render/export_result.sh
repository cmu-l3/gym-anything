#!/bin/bash
echo "=== Exporting retro_vga_framerange_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/retro_vga"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Capture Final State Evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
# Count image files (PNG, TGA, TIF)
FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) -type f 2>/dev/null | wc -l)
FILE_COUNT=${FILE_COUNT:-0}

# Count new files (created after task start)
NEW_FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) -type f -newer /tmp/task_start_timestamp 2>/dev/null | wc -l)
NEW_FILE_COUNT=${NEW_FILE_COUNT:-0}

# Calculate directory size
TOTAL_SIZE_KB=0
if [ -d "$OUTPUT_DIR" ]; then
    TOTAL_SIZE_KB=$(du -sk "$OUTPUT_DIR" 2>/dev/null | awk '{print $1}')
fi

# 3. Analyze Image Dimensions (Resolution)
# check the first image found
FIRST_IMG=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" -o -name "*.tif" \) -type f 2>/dev/null | head -n 1)
IMG_WIDTH=0
IMG_HEIGHT=0

if [ -n "$FIRST_IMG" ]; then
    # Use python to get dimensions safely
    DIMS=$(python3 -c "
import sys
try:
    from PIL import Image
    img = Image.open('$FIRST_IMG')
    print(f'{img.width} {img.height}')
except:
    print('0 0')
" 2>/dev/null)
    IMG_WIDTH=$(echo "$DIMS" | awk '{print $1}')
    IMG_HEIGHT=$(echo "$DIMS" | awk '{print $2}')
fi

# 4. Create JSON Result
RESULT_FILE="/tmp/retro_vga_result.json"
cat > "$RESULT_FILE" << EOF
{
    "file_count": $FILE_COUNT,
    "new_file_count": $NEW_FILE_COUNT,
    "total_size_kb": $TOTAL_SIZE_KB,
    "img_width": $IMG_WIDTH,
    "img_height": $IMG_HEIGHT,
    "task_start": $TASK_START,
    "output_dir": "$OUTPUT_DIR"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="