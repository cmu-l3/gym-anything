#!/bin/bash
echo "=== Exporting Cartesian Coordinates Result ==="

source /workspace/scripts/task_utils.sh

# 1. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check if GCompris is still running (Evidence of not crashing)
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Check for Data Modification (Anti-gaming)
# GCompris updates local files when activities are played/completed.
# We check if any file in the data directory was modified AFTER task start.
DATA_MODIFIED="false"
CONFIG_DIR="/home/ga/.config/gcompris-qt"
SHARE_DIR="/home/ga/.local/share/GCompris"

# Check config dir
if [ -d "$CONFIG_DIR" ]; then
    count=$(find "$CONFIG_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        DATA_MODIFIED="true"
    fi
fi

# Check share dir (progress data usually lives here)
if [ "$DATA_MODIFIED" = "false" ] && [ -d "$SHARE_DIR" ]; then
    count=$(find "$SHARE_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$count" -gt 0 ]; then
        DATA_MODIFIED="true"
    fi
fi

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "data_modified": $DATA_MODIFIED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="