#!/bin/bash
echo "=== Exporting Super Brain results ==="

source /workspace/scripts/task_utils.sh

# 1. Record Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check for Activity Data Creation
# GCompris creates/updates files in ~/.local/share/GCompris when activities are played/completed
DATA_DIR="/home/ga/.local/share/GCompris"
ACTIVITY_DATA_MODIFIED="false"

# Check if any file in data dir was modified after start time
if [ -d "$DATA_DIR" ]; then
    # Find files modified since task start
    MODIFIED_FILES=$(find "$DATA_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$MODIFIED_FILES" -gt 0 ]; then
        ACTIVITY_DATA_MODIFIED="true"
        echo "Detected $MODIFIED_FILES modified data files (evidence of activity)."
    fi
fi

# 3. Check if App is Still Running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "activity_data_modified": $ACTIVITY_DATA_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="