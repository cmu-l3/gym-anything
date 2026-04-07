#!/bin/bash
echo "=== Exporting generate_walk_pose_sheet result ==="

OUTPUT_FILE="/home/ga/OpenToonz/output/pose_sheet/poses.png"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check output file
FILE_EXISTS="false"
FILE_SIZE_KB=0
FILE_NEWER="false"
IMG_WIDTH=0
IMG_HEIGHT=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_KB=$(du -k "$OUTPUT_FILE" | cut -f1)
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_NEWER="true"
    fi

    # Get dimensions using Python (available in env)
    DIMS=$(python3 -c "
from PIL import Image
try:
    img = Image.open('$OUTPUT_FILE')
    print(f'{img.width} {img.height}')
except:
    print('0 0')
" 2>/dev/null || echo "0 0")
    
    IMG_WIDTH=$(echo "$DIMS" | cut -d' ' -f1)
    IMG_HEIGHT=$(echo "$DIMS" | cut -d' ' -f2)
fi

# Write result JSON
RESULT_FILE="/tmp/task_result.json"
cat > "$RESULT_FILE" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_FILE",
    "file_size_kb": $FILE_SIZE_KB,
    "file_newer_than_start": $FILE_NEWER,
    "image_width": $IMG_WIDTH,
    "image_height": $IMG_HEIGHT,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="