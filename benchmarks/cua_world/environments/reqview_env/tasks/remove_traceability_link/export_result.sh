#!/bin/bash
echo "=== Exporting remove_traceability_link results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check SRS.json modification status
SRS_PATH=$(find /home/ga/Documents/ReqView -name "SRS.json" -type f | grep "remove_link_task" | head -1)
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$SRS_PATH" ]; then
    FILE_SIZE=$(stat -c %s "$SRS_PATH")
    FILE_MTIME=$(stat -c %Y "$SRS_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Create Result JSON
# We don't analyze the JSON here; we let the python verifier do the complex logic.
# We just pass paths and basic file stats.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_path": "$SRS_PATH",
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"