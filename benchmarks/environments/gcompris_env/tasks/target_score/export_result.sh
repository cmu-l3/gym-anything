#!/bin/bash
set -e
echo "=== Exporting target_score results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if application is still running
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/target_final.png

# Check for any modified config/score files (evidence of activity)
# GCompris-qt usually stores database in ~/.local/share/GCompris/gcompris-qt/
DATA_DIR="/home/ga/.local/share/GCompris/gcompris-qt"
FILES_MODIFIED="false"
if [ -d "$DATA_DIR" ]; then
    # Find files modified after task start
    MOD_COUNT=$(find "$DATA_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$MOD_COUNT" -gt 0 ]; then
        FILES_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "files_modified": $FILES_MODIFIED,
    "final_screenshot_path": "/tmp/target_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="