#!/bin/bash
echo "=== Exporting create_hvac_plan results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot immediately
take_screenshot /tmp/task_final.png

# 2. Gather file information
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EDDX_PATH="/home/ga/Documents/server_room_hvac.eddx"
PNG_PATH="/home/ga/Documents/server_room_hvac.png"

# Function to check file details
check_file() {
    local path=$1
    if [ -f "$path" ]; then
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during_task, \"path\": \"$path\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false, \"path\": \"$path\"}"
    fi
}

EDDX_INFO=$(check_file "$EDDX_PATH")
PNG_INFO=$(check_file "$PNG_PATH")

# 3. Check if App is still running
APP_RUNNING="false"
if is_edrawmax_running; then
    APP_RUNNING="true"
fi

# 4. Generate Result JSON
# Using a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "eddx_file": $EDDX_INFO,
    "png_file": $PNG_INFO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json