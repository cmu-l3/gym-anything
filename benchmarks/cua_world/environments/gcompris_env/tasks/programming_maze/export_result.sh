#!/bin/bash
echo "=== Exporting Programming Maze results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# capture final state
take_screenshot /tmp/task_final.png

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Define expected files
FILE_L1="/home/ga/Documents/programming_maze_complete.png"
FILE_L2="/home/ga/Documents/programming_maze_level2.png"

# Helper to check file status
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        
        # Verify file was created DURING the task
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"valid_time\": true, \"size\": $size}"
        else
            echo "{\"exists\": true, \"valid_time\": false, \"size\": $size}"
        fi
    else
        echo "{\"exists\": false, \"valid_time\": false, \"size\": 0}"
    fi
}

# Check both screenshots
L1_STATUS=$(check_file "$FILE_L1")
L2_STATUS=$(check_file "$FILE_L2")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "level_1_screenshot": $L1_STATUS,
    "level_2_screenshot": $L2_STATUS,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="