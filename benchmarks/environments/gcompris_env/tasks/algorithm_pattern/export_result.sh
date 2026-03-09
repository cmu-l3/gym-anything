#!/bin/bash
echo "=== Exporting algorithm_pattern results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper function to check a level file
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local size
        size=$(stat -c%s "$fpath" 2>/dev/null || echo "0")
        local mtime
        mtime=$(stat -c%Y "$fpath" 2>/dev/null || echo "0")
        
        # Check if created during task
        local created_during=false
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during=true
        fi
        
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

# Check all three expected files
L1_JSON=$(check_file "/home/ga/algorithm_level1.png")
L2_JSON=$(check_file "/home/ga/algorithm_level2.png")
L3_JSON=$(check_file "/home/ga/algorithm_level3.png")

# Check if GCompris is still running
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# Take final screenshot of the desktop
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "level1": $L1_JSON,
    "level2": $L2_JSON,
    "level3": $L3_JSON
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="