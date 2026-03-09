#!/bin/bash
set -e
echo "=== Exporting Peroxide Former Identification Results ==="

# Define paths
OUTPUT_FILE="/home/ga/Desktop/peroxide_audit_report.txt"
START_TIME_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")

# Check output file status
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE_BYTES=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Firefox is still running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# Create result JSON
# Note: We do NOT put the file content here. The verifier will copy the actual text file.
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions for copy_from_env
chmod 666 "$RESULT_JSON" 2>/dev/null || true
if [ -f "$OUTPUT_FILE" ]; then
    chmod 666 "$OUTPUT_FILE" 2>/dev/null || true
fi

echo "Result JSON saved to $RESULT_JSON"
echo "=== Export complete ==="