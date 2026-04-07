#!/bin/bash
echo "=== Exporting Task Results ==="

# Output directory defined in task
OUTPUT_DIR="/home/ga/OpenToonz/output/keyframe_still"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Find the rendered file
# OpenToonz might name it frame008.png, frame008.0008.png, frame.0008.png, etc.
# We look for any PNG file in the target directory
FOUND_FILE=$(find "$OUTPUT_DIR" -name "*.png" -type f | head -n 1)

OUTPUT_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
IMG_WIDTH=0
IMG_HEIGHT=0
IMG_MODE="Unknown"
HAS_TRANSPARENCY="false"
MIN_ALPHA=255

if [ -n "$FOUND_FILE" ]; then
    echo "Found output file: $FOUND_FILE"
    OUTPUT_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$FOUND_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check size
    FILE_SIZE=$(stat -c %s "$FOUND_FILE")

    # Analyze Image Content with Python
    # We check: Dimensions, Mode (RGBA), and specific Alpha channel values
    ANALYSIS=$(python3 -c "
import sys
from PIL import Image

try:
    img = Image.open('$FOUND_FILE')
    print(f'WIDTH={img.width}')
    print(f'HEIGHT={img.height}')
    print(f'MODE={img.mode}')
    
    has_transparency = 'false'
    min_alpha = 255
    
    if img.mode == 'RGBA':
        # Get alpha channel data
        alpha = img.split()[3]
        min_a, max_a = alpha.getextrema()
        min_alpha = min_a
        # If minimum alpha is less than 255, we have transparency
        if min_a < 255:
            has_transparency = 'true'
            
    print(f'HAS_TRANSPARENCY={has_transparency}')
    print(f'MIN_ALPHA={min_alpha}')
    
except Exception as e:
    print(f'ERROR={str(e)}')
")
    
    # Parse Python output
    IMG_WIDTH=$(echo "$ANALYSIS" | grep "WIDTH=" | cut -d'=' -f2)
    IMG_HEIGHT=$(echo "$ANALYSIS" | grep "HEIGHT=" | cut -d'=' -f2)
    IMG_MODE=$(echo "$ANALYSIS" | grep "MODE=" | cut -d'=' -f2)
    HAS_TRANSPARENCY=$(echo "$ANALYSIS" | grep "HAS_TRANSPARENCY=" | cut -d'=' -f2)
    MIN_ALPHA=$(echo "$ANALYSIS" | grep "MIN_ALPHA=" | cut -d'=' -f2)
else
    echo "No PNG file found in $OUTPUT_DIR"
fi

# Create Result JSON
JSON_FILE="/tmp/task_result.json"
cat > "$JSON_FILE" << EOF
{
    "task_start": $TASK_START_TIME,
    "task_end": $TASK_END_TIME,
    "output_exists": $OUTPUT_EXISTS,
    "file_path": "$FOUND_FILE",
    "file_size_bytes": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "image_width": ${IMG_WIDTH:-0},
    "image_height": ${IMG_HEIGHT:-0},
    "image_mode": "${IMG_MODE:-Unknown}",
    "has_transparency": ${HAS_TRANSPARENCY:-false},
    "min_alpha_value": ${MIN_ALPHA:-255},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions so agent/verifier can read it
chmod 666 "$JSON_FILE" 2>/dev/null || true

echo "Result JSON generated:"
cat "$JSON_FILE"
echo "=== Export Complete ==="