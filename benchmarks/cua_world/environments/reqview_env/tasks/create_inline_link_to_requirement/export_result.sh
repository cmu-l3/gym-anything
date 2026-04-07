#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check SRS file status
SRS_PATH="/home/ga/Documents/ReqView/create_inline_link_project/documents/SRS.json"
SRS_MODIFIED="false"
SRS_SIZE="0"

if [ -f "$SRS_PATH" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_PATH" 2>/dev/null || echo "0")
    SRS_SIZE=$(stat -c %s "$SRS_PATH" 2>/dev/null || echo "0")
    
    # Check if modified after task start
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        SRS_MODIFIED="true"
    fi
fi

# 3. Capture final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_modified": $SRS_MODIFIED,
    "srs_path": "$SRS_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="