#!/bin/bash
set -euo pipefail

echo "=== Exporting School Enrollment Projection Result ==="

# Source ONLYOFFICE task utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || \
su - ga -c "DISPLAY=:1 import -window root /tmp/task_final.png" 2>/dev/null || true

# Attempt to save and close the application to ensure data flushes to disk
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

# Check for the expected output file
OUTPUT_PATH="/home/ga/Documents/Spreadsheets/enrollment_projections.xlsx"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

TASK_START=$(cat /tmp/enrollment_projection_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
    
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $OUTPUT_PATH ($FILE_SIZE bytes)"
else
    echo "Output file not found at exact path. Checking directory..."
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

# Write metadata for verifier
cat > /tmp/enrollment_projection_result.json << JSONEOF
{
  "task_name": "school_enrollment_projection",
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "output_file_exists": $FILE_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "output_size_bytes": $FILE_SIZE,
  "screenshot_path": "/tmp/task_final.png"
}
JSONEOF

echo "Result JSON saved to /tmp/enrollment_projection_result.json"
echo "=== Export Complete ==="