#!/bin/bash
echo "=== Exporting print_employee_badge results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/badge.pdf"
EXPORT_FILE="/tmp/badge_artifact.pdf"

# 1. Check File Existence
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    # Check if modified/created during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_FRESH="true"
    else
        IS_FRESH="false"
    fi
    
    # Prepare file for extraction by verifier
    cp "$TARGET_FILE" "$EXPORT_FILE"
    chmod 666 "$EXPORT_FILE"
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    IS_FRESH="false"
fi

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_fresh": $IS_FRESH,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "=== Export Complete ==="