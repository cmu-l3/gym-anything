#!/bin/bash
echo "=== Exporting OR Turnover Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Stop the window poller
if [ -f /tmp/poller_pid.txt ]; then
    POLLER_PID=$(cat /tmp/poller_pid.txt)
    kill "$POLLER_PID" 2>/dev/null || true
    echo "Window poller stopped"
fi

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check OpenICE status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Check Turnover Log File
LOG_FILE="/home/ga/Desktop/turnover_log.txt"
LOG_EXISTS="false"
LOG_CONTENT=""
if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_CONTENT=$(cat "$LOG_FILE" | tr '\n' ' ')
fi

# Prepare Window History Log for verification
# We ensure the file is readable
if [ ! -f /tmp/window_history.log ]; then
    echo "Warning: Window history log not found"
    touch /tmp/window_history.log
fi

# Create result JSON
# We embed the entire window history log into the JSON for the verifier to parse
# This might be large, so we escape it carefully
HISTORY_CONTENT=$(cat /tmp/window_history.log | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')

create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "log_file_exists": $LOG_EXISTS,
    "log_file_content": "$(echo "$LOG_CONTENT" | sed 's/"/\\"/g')",
    "window_history_log": $HISTORY_CONTENT,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
echo "Log file exists: $LOG_EXISTS"
cat /tmp/task_result.json