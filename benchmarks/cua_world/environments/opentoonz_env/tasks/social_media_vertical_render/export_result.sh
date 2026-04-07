#!/bin/bash
echo "=== Exporting social_media_vertical_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/vertical_social"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize metrics
FRAME_COUNT=0
IMG_WIDTH=0
IMG_HEIGHT=0
FILES_NEWER=0
TOTAL_SIZE_KB=0

if [ -d "$OUTPUT_DIR" ]; then
    # Count PNG/TGA files
    FRAME_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | wc -l)
    
    # Get total size
    TOTAL_SIZE_KB=$(du -sk "$OUTPUT_DIR" 2>/dev/null | awk '{print $1}')
    
    # Check timestamps
    FILES_NEWER=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" \) -newer /tmp/task_start_timestamp -type f 2>/dev/null | wc -l)
    
    # Check dimensions of the first valid image
    FIRST_IMG=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.png" -o -name "*.tga" \) -type f 2>/dev/null | head -1)
    
    if [ -n "$FIRST_IMG" ]; then
        DIMS=$(python3 -c "
import sys
try:
    from PIL import Image
    img = Image.open('$FIRST_IMG')
    print(f'{img.width} {img.height}')
except Exception:
    print('0 0')
" 2>/dev/null)
        IMG_WIDTH=$(echo "$DIMS" | awk '{print $1}')
        IMG_HEIGHT=$(echo "$DIMS" | awk '{print $2}')
    fi
fi

# Create result JSON
RESULT_FILE="/tmp/task_result.json"
cat > "$RESULT_FILE" << EOF
{
    "frame_count": $FRAME_COUNT,
    "img_width": $IMG_WIDTH,
    "img_height": $IMG_HEIGHT,
    "files_newer_than_start": $FILES_NEWER,
    "total_size_kb": $TOTAL_SIZE_KB,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false"),
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result:"
cat "$RESULT_FILE"