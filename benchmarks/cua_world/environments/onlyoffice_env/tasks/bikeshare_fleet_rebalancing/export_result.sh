#!/bin/bash
set -euo pipefail

echo "=== Exporting Bikeshare Fleet Rebalancing Task Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Attempt to save and close gracefully if OnlyOffice is open
if pgrep -f "onlyoffice-desktopeditors" > /dev/null; then
    if [ -f /workspace/scripts/task_utils.sh ]; then
        source /workspace/scripts/task_utils.sh
        focus_onlyoffice_window || true
        save_document ga :1
        sleep 2
        close_onlyoffice ga :1
        sleep 2
    fi
fi

TARGET_PATH="/home/ga/Documents/Spreadsheets/cabi_rebalancing_plan.xlsx"

if [ -f "$TARGET_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$TARGET_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$TARGET_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="