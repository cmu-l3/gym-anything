#!/bin/bash
echo "=== Exporting Wolf, Goat, Cabbage Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected file paths
MID_STEP_PATH="/home/ga/Documents/river_mid_step.png"
SOLVED_PATH="/home/ga/Documents/river_solved.png"

# Helper function to get file info
get_file_info() {
    local path="$1"
    if [ -f "$path" ]; then
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check files
MID_INFO=$(get_file_info "$MID_STEP_PATH")
SOLVED_INFO=$(get_file_info "$SOLVED_PATH")

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final system screenshot (backup evidence)
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "mid_step_file": $MID_INFO,
    "solved_file": $SOLVED_INFO,
    "system_screenshot": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="