#!/bin/bash
echo "=== Exporting Submarine Buoyancy Pilot results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
DEPTH_IMG="/home/ga/Documents/submarine_depth.png"
SURF_IMG="/home/ga/Documents/submarine_surface.png"
LOG_FILE="/home/ga/Documents/captains_log.txt"

# Helper to check file status
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"created_during_task\": true, \"size\": $size, \"path\": \"$path\"}"
        else
            echo "{\"exists\": true, \"created_during_task\": false, \"size\": $size, \"path\": \"$path\"}"
        fi
    else
        echo "{\"exists\": false, \"created_during_task\": false, \"size\": 0, \"path\": \"\"}"
    fi
}

# Check files
DEPTH_STATUS=$(check_file "$DEPTH_IMG")
SURF_STATUS=$(check_file "$SURF_IMG")
LOG_STATUS=$(check_file "$LOG_FILE")

# Check log content (basic keyword check in bash, detailed in python)
LOG_CONTENT=""
if [ -f "$LOG_FILE" ]; then
    # Read first 500 chars, escape quotes for JSON
    LOG_CONTENT=$(head -c 500 "$LOG_FILE" | tr '\n' ' ' | sed 's/"/\\"/g')
fi

# Check if GCompris is still running
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "depth_screenshot": $DEPTH_STATUS,
    "surface_screenshot": $SURF_STATUS,
    "log_file": $LOG_STATUS,
    "log_content_preview": "$LOG_CONTENT"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json