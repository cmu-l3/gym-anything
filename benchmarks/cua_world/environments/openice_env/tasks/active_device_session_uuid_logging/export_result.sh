#!/bin/bash
echo "=== Exporting active_device_session_uuid_logging result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Process Logs to extract Ground Truth
# We only care about logs written during the task
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")

# Extract the tail of the log (lines added during task)
# We filter for lines that might contain UUIDs and Device names to keep the file size small for verification
# Common pattern: "DeviceConnectivityAdapter... Device connected: <UUID> ... (<Type>)"
TAIL_LOG="/tmp/task_log_tail.txt"
if [ -f "$LOG_FILE" ]; then
    tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" > "$TAIL_LOG"
else
    touch "$TAIL_LOG"
fi

# 2. Check Agent Output File
OUTPUT_FILE="/home/ga/Desktop/active_device_inventory.csv"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
fi

# 3. Check OpenICE State
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# 4. Create Result JSON
# We don't embed the log content here to avoid JSON escaping issues. 
# The verifier will read the log tail file directly.
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "output_file_exists": $FILE_EXISTS,
    "output_file_size": $FILE_SIZE,
    "output_file_mtime": $FILE_MTIME,
    "log_tail_path": "$TAIL_LOG",
    "output_file_path": "$OUTPUT_FILE",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Ensure the log tail file and agent output are readable by the verifier (via copy_from_env)
chmod 644 "$TAIL_LOG" 2>/dev/null || true
if [ -f "$OUTPUT_FILE" ]; then
    chmod 644 "$OUTPUT_FILE" 2>/dev/null || true
fi

echo "=== Export Complete ==="
cat /tmp/task_result.json