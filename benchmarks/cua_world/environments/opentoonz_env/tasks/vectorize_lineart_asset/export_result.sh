#!/bin/bash
echo "=== Exporting vectorize_lineart_asset result ==="

# Define paths
OUTPUT_FILE="/home/ga/OpenToonz/outputs/vectorized/director_sketch.pli"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE=0
IS_NEW="false"
FILE_TYPE="unknown"
IS_RASTER="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi

    # Check file type using 'file' command
    FILE_TYPE_OUTPUT=$(file -b --mime-type "$OUTPUT_FILE")
    FILE_TYPE="$FILE_TYPE_OUTPUT"
    
    # Check magic bytes to detect if it's just a renamed PNG/JPG
    # PNG signature: 89 50 4E 47
    # JPG signature: FF D8 FF
    HEADER_HEX=$(xxd -p -l 4 "$OUTPUT_FILE" | tr '[:lower:]' '[:upper:]')
    
    if [[ "$HEADER_HEX" == "89504E47" ]]; then
        IS_RASTER="true"
        FILE_TYPE="image/png (renamed)"
    elif [[ "$HEADER_HEX" == FFD8FF* ]]; then
        IS_RASTER="true"
        FILE_TYPE="image/jpeg (renamed)"
    fi
fi

# Generate JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "is_new_file": $IS_NEW,
    "file_type_mime": "$FILE_TYPE",
    "is_raster_disguised": $IS_RASTER,
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