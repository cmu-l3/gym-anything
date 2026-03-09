#!/bin/bash
set -e
echo "=== Exporting Chronos Sequence results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris-qt" > /dev/null || pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Check for data modification (GCompris stores progress in SQLite or config)
# Location varies by version, usually ~/.local/share/GCompris/ or ~/.config/gcompris-qt/
DATA_MODIFIED="false"
GCOMPRIS_DATA_DIR="/home/ga/.local/share/GCompris"
GCOMPRIS_CONFIG_DIR="/home/ga/.config/gcompris-qt"

# Check if any file in data dirs was modified after start time
if [ -d "$GCOMPRIS_DATA_DIR" ]; then
    RECENT_FILES=$(find "$GCOMPRIS_DATA_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$RECENT_FILES" -gt 0 ]; then
        DATA_MODIFIED="true"
    fi
fi

if [ "$DATA_MODIFIED" = "false" ] && [ -d "$GCOMPRIS_CONFIG_DIR" ]; then
    RECENT_CONFIG=$(find "$GCOMPRIS_CONFIG_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$RECENT_CONFIG" -gt 0 ]; then
        DATA_MODIFIED="true"
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "data_modified": $DATA_MODIFIED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with read permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"