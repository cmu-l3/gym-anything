#!/bin/bash
set -e
echo "=== Exporting Tangram Puzzle Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/tangram_final.png

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Check for interaction evidence (database modification)
DB_FILE="/home/ga/.local/share/gcompris-qt/gcompris-internal.db"
DB_MODIFIED="false"
DB_SIZE_CHANGE="0"

if [ -f "$DB_FILE" ]; then
    DB_MTIME=$(stat -c %Y "$DB_FILE" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
    
    # Check size difference if initial existed
    if [ -f "/tmp/initial_gcompris.db" ]; then
        INIT_SIZE=$(stat -c %s "/tmp/initial_gcompris.db" || echo "0")
        CURR_SIZE=$(stat -c %s "$DB_FILE" || echo "0")
        DB_SIZE_CHANGE=$((CURR_SIZE - INIT_SIZE))
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "db_modified": $DB_MODIFIED,
    "db_size_change_bytes": $DB_SIZE_CHANGE,
    "final_screenshot_path": "/tmp/tangram_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="