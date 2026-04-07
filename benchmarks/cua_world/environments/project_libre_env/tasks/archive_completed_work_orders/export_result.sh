#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
ARCHIVE_FILE="/home/ga/Projects/archive.xml"
ACTIVE_FILE="/home/ga/Projects/active_log.xml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper function to get file stats
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Collect info
ARCHIVE_INFO=$(get_file_info "$ARCHIVE_FILE")
ACTIVE_INFO=$(get_file_info "$ACTIVE_FILE")
INITIAL_COUNTS=$(cat /tmp/initial_counts.json 2>/dev/null || echo "{}")

# Check if app running
APP_RUNNING=$(pgrep -f "projectlibre" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "archive_file": $ARCHIVE_INFO,
    "active_file": $ACTIVE_INFO,
    "initial_counts": $INITIAL_COUNTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"