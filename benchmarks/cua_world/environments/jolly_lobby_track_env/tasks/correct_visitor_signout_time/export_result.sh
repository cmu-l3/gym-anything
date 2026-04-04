#!/bin/bash
echo "=== Exporting correct_visitor_signout_time result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check for Output File
EXPORT_PATH="/home/ga/Documents/corrected_log.csv"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

TASK_START=$(cat /tmp/correct_visitor_signout_time_start_time 2>/dev/null || echo "0")

if [ -f "$EXPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_PATH")
    
    # Check timestamp
    FILE_MTIME=$(stat -c%Y "$EXPORT_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Read content (safe read, first 50 lines to avoid massive JSON)
    # Encode to base64 to avoid JSON breaking characters, or just cat if simple
    FILE_CONTENT=$(head -n 50 "$EXPORT_PATH" | base64 -w 0)
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$EXPORT_PATH",
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_b64": "$FILE_CONTENT",
    "timestamp": "$(date -Iseconds)"
}
EOF

# 4. Save to public location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"