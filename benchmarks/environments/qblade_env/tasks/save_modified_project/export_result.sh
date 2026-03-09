#!/bin/bash
set -e
echo "=== Exporting save_modified_project results ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_MD5=$(cat /tmp/original_project_md5.txt 2>/dev/null || echo "none")

OUTPUT_FILE="/home/ga/Documents/projects/turbine_pitch3.wpa"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize variables
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
MD5_DIFFERENT="false"
PITCH_VALUE_FOUND="false"
QBLADE_RUNNING="false"

# Check output file
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check timestamp
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check MD5 difference
    CURRENT_MD5=$(md5sum "$OUTPUT_FILE" | awk '{print $1}')
    if [ "$CURRENT_MD5" != "$ORIGINAL_MD5" ]; then
        MD5_DIFFERENT="true"
    fi
    
    # Content check: Look for "Pitch" and "3" nearby in the .wpa (XML/Text format)
    # QBlade .wpa files are text based. We look for the parameter.
    # Simple grep check for the value 3 in context of pitch
    if grep -i "pitch" "$OUTPUT_FILE" | grep -E "3\.0|3\.00| 3 |>3<|=3" >/dev/null; then
        PITCH_VALUE_FOUND="true"
    elif grep -E "^3\.000000$" "$OUTPUT_FILE" >/dev/null; then
        # Sometimes values are on their own lines in QBlade files
        PITCH_VALUE_FOUND="true"
    fi
fi

# Check if QBlade is running
if pgrep -f "[Qq][Bb]lade" > /dev/null; then
    QBLADE_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "md5_different_from_original": $MD5_DIFFERENT,
    "pitch_value_found": $PITCH_VALUE_FOUND,
    "qblade_running": $QBLADE_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="