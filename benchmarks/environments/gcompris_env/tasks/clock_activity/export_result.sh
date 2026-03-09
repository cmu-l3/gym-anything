#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Clock Activity Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if GCompris is still running
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# Helper function to check file stats
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local fsize=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local fmtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local created_in_task="false"
        if [ "$fmtime" -gt "$TASK_START" ]; then
            created_in_task="true"
        fi
        echo "{\"exists\": true, \"size\": $fsize, \"created_during_task\": $created_in_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check specific files
BEFORE_STATS=$(check_file "/tmp/clock_before.png")
AFTER_STATS=$(check_file "/tmp/clock_after.png")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "clock_before": $BEFORE_STATS,
    "clock_after": $AFTER_STATS,
    "initial_screenshot_path": "/tmp/task_initial.png",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="