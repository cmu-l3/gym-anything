#!/bin/bash
echo "=== Exporting scale_balance_activity result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if App is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Check for database/config modification (weak signal of interaction)
# GCompris Qt usually uses sqlite for progress
DB_FILE="/home/ga/.local/share/GCompris/gcompris-sqlite.db"
DB_MODIFIED="false"
if [ -f "$DB_FILE" ]; then
    DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
fi

# 3. Take final screenshot
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
    "db_modified": $DB_MODIFIED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="