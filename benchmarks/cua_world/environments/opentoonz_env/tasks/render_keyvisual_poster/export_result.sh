#!/bin/bash
echo "=== Exporting render_keyvisual_poster results ==="

# Paths
OUTPUT_DIR="/home/ga/OpenToonz/output/poster"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot for VLM verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze Output Files
# We look for PNG files in the output directory
# Note: OpenToonz might append frame numbers (e.g., keyvisual.0010.png) even for single frames
FOUND_FILES=$(find "$OUTPUT_DIR" -name "*.png" -type f)
FILE_COUNT=$(echo "$FOUND_FILES" | grep -c "\.png" || echo "0")

# Initialize result variables
IMG_WIDTH=0
IMG_HEIGHT=0
FILE_SIZE_BYTES=0
IS_NEWER="false"
PIXEL_STD_DEV=0
FILENAME=""

if [ "$FILE_COUNT" -gt 0 ]; then
    # Pick the largest file (likely the render)
    FILENAME=$(ls -S "$OUTPUT_DIR"/*.png | head -1)
    
    # Get file stats
    FILE_MTIME=$(stat -c %Y "$FILENAME")
    FILE_SIZE_BYTES=$(stat -c %s "$FILENAME")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEWER="true"
    fi

    # Use Python to analyze image content and dimensions
    # We use a python one-liner to be robust against missing tools, relying on system python + pillow
    # which is installed in the env
    read IMG_WIDTH IMG_HEIGHT PIXEL_STD_DEV <<< $(python3 -c "
import sys
try:
    from PIL import Image
    import numpy as np
    img = Image.open('$FILENAME')
    w, h = img.size
    # Convert to greyscale for simple variance check
    arr = np.array(img.convert('L'))
    std_dev = np.std(arr)
    print(f'{w} {h} {std_dev:.2f}')
except Exception as e:
    print('0 0 0')
")
fi

# 3. Create JSON Result
# Using a temp file to ensure atomic write and permission handling
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_count": $FILE_COUNT,
    "found_filename": "$(basename "$FILENAME")",
    "width": $IMG_WIDTH,
    "height": $IMG_HEIGHT,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "is_newer_than_start": $IS_NEWER,
    "pixel_std_dev": $PIXEL_STD_DEV,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false")
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json