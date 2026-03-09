#!/bin/bash
# export_result.sh - Post-task hook for hazard_threshold_logic_assessment
set -e

echo "=== Exporting hazard_threshold_logic_assessment result ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/alarm_logic_assessment.csv"
TASK_START_FILE="/tmp/task_start_time"
RESULT_JSON="/tmp/task_result.json"

# Get task start time
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Firefox is still running (good practice)
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
# We don't read the CSV content into JSON here; Python verifier will read the file directly
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions for the verifier to read
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result exported to $RESULT_JSON"
echo "=== Export complete ==="