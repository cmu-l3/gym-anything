#!/bin/bash
echo "=== Exporting Tower of Hanoi result ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Check for GCompris configuration/data modification (Anti-gaming)
# This checks if the agent actually interacted with the application enough to trigger auto-saves/config updates
DATA_DIR="/home/ga/.local/share/GCompris"
CONFIG_DIR="/home/ga/.config/gcompris-qt"
FILES_MODIFIED="false"

# Check for files modified after task start
if [ -d "$DATA_DIR" ]; then
    MOD_COUNT=$(find "$DATA_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$MOD_COUNT" -gt 0 ]; then
        FILES_MODIFIED="true"
    fi
fi
if [ "$FILES_MODIFIED" == "false" ] && [ -d "$CONFIG_DIR" ]; then
    MOD_COUNT=$(find "$CONFIG_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$MOD_COUNT" -gt 0 ]; then
        FILES_MODIFIED="true"
    fi
fi

# 3. Capture final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "files_modified": $FILES_MODIFIED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result to known location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="