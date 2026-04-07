#!/bin/bash
set -e
echo "=== Exporting export_profile_image result ==="

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
FILE_TYPE="none"
FOUND_PATH=""

# Search for any file matching the required name pattern in the Documents folder
FOUND_FILE=$(find /home/ga/Documents -maxdepth 1 -type f -iname "*deep_dive_profile*" | head -n 1)

if [ -n "$FOUND_FILE" ]; then
    FOUND_PATH="$FOUND_FILE"
    OUTPUT_EXISTS="true"
    
    # Get file size
    FILE_SIZE=$(stat -c %s "$FOUND_FILE" 2>/dev/null || echo "0")
    
    # Get modification time to check if created during task
    MTIME=$(stat -c %Y "$FOUND_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Get file type (e.g. "PNG image data, 1920 x 1080...")
    # Clean output to prevent JSON breakage
    FILE_TYPE=$(file -b "$FOUND_FILE" | sed 's/"/\\"/g' | tr -d '\n')
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Write structured JSON for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "file_type": "$FILE_TYPE",
    "found_path": "$FOUND_PATH"
}
EOF

# Make result readable by verifier
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="