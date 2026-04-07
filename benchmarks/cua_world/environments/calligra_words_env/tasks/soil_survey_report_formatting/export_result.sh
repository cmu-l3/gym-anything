#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Soil Survey Report Formatting Result ==="

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi

# Take final screenshot BEFORE closing the application
take_screenshot /tmp/calligra_soil_survey_report_post_task.png ga

# Check file modification time compared to start time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
FILE_PATH="/home/ga/Documents/soil_survey_report.odt"

if [ -f "$FILE_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        echo "File was successfully modified during the task session."
    else
        echo "WARNING: File modification time is older than task start time."
    fi
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" "$FILE_PATH" || true
else
    echo "Warning: $FILE_PATH is missing"
fi

# Gracefully ask Calligra to quit, without forcing a save 
# (the agent must have saved it themselves)
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

# Cleanup processes
kill_calligra_processes

echo "=== Export Complete ==="