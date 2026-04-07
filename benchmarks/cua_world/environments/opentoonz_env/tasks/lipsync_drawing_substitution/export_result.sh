#!/bin/bash
echo "=== Exporting Lip Sync Result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/lipsync"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize variables
OUTPUT_EXISTS="false"
FILE_COUNT=0
FILES_CREATED_DURING_TASK="false"
FRAME_5_MEAN=0
FRAME_15_MEAN=0
FRAME_25_MEAN=0

# Check if output directory has files
if [ -d "$OUTPUT_DIR" ]; then
    # Count PNG files
    FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.png" | wc -l)
    
    if [ "$FILE_COUNT" -gt 0 ]; then
        OUTPUT_EXISTS="true"
        
        # Check timestamps
        NEW_FILES=$(find "$OUTPUT_DIR" -name "*.png" -newer /tmp/task_start_time.txt | wc -l)
        if [ "$NEW_FILES" -ge "$FILE_COUNT" ]; then
            FILES_CREATED_DURING_TASK="true"
        fi

        # Measure pixel brightness mean (0-65535 or 0-255 depending on version, usually normalized in verification)
        # We look for specific frame numbers. OpenToonz often names them name.0001.png or name_0001.png
        
        # Helper to find a specific frame file (e.g., frame 5)
        # Tries various naming conventions: *0005.png, *005.png, etc.
        find_frame() {
            local num=$1
            # Pad with zeros to 4 digits (OpenToonz default)
            local padded=$(printf "%04d" $num)
            find "$OUTPUT_DIR" -name "*${padded}.png" | head -1
        }
        
        IMG_5=$(find_frame 5)
        IMG_15=$(find_frame 15)
        IMG_25=$(find_frame 25)

        # Get mean brightness using ImageMagick
        if [ -f "$IMG_5" ]; then
            FRAME_5_MEAN=$(convert "$IMG_5" -format "%[mean]" info:)
        fi
        if [ -f "$IMG_15" ]; then
            FRAME_15_MEAN=$(convert "$IMG_15" -format "%[mean]" info:)
        fi
        if [ -f "$IMG_25" ]; then
            FRAME_25_MEAN=$(convert "$IMG_25" -format "%[mean]" info:)
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_count": $FILE_COUNT,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "frame_5_mean": ${FRAME_5_MEAN:-0},
    "frame_15_mean": ${FRAME_15_MEAN:-0},
    "frame_25_mean": ${FRAME_25_MEAN:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="