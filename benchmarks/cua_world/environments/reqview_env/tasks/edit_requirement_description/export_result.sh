#!/bin/bash
echo "=== Exporting edit_requirement_description result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check SRS file status
# Retrieve path from metadata or default
SRS_PATH="/home/ga/Documents/ReqView/edit_req_desc_project/documents/SRS.json"
if [ -f "/tmp/task_metadata.json" ]; then
    SRS_PATH=$(python3 -c "import json; print(json.load(open('/tmp/task_metadata.json')).get('srs_path', '$SRS_PATH'))" 2>/dev/null || echo "$SRS_PATH")
fi

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"
MOD_TIME="0"

if [ -f "$SRS_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$SRS_PATH")
    MOD_TIME=$(stat -c %Y "$SRS_PATH")
    
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Check if app is running
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "file_path": "$SRS_PATH",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"