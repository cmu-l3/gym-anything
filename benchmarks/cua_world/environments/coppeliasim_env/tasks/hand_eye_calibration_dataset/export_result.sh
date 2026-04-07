#!/bin/bash
echo "=== Exporting hand_eye_calibration_dataset Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/hand_eye_calibration_start_ts 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/CoppeliaSim/exports/hand_eye_dataset.csv"
JSON_PATH="/home/ga/Documents/CoppeliaSim/exports/dataset_report.json"

# Take final screenshot
take_screenshot /tmp/hand_eye_calibration_end_screenshot.png

# Gather metadata about the files
CSV_EXISTS="false"
CSV_MTIME="0"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
fi

JSON_EXISTS="false"
JSON_MTIME="0"
if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
fi

# Write summary JSON for the verifier (actual file content will be copied in verifier.py)
cat > /tmp/hand_eye_task_result.json << EOF
{
    "task_start_ts": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_mtime": $CSV_MTIME,
    "json_exists": $JSON_EXISTS,
    "json_mtime": $JSON_MTIME
}
EOF

echo "Task result metadata written to /tmp/hand_eye_task_result.json"
echo "=== Export Complete ==="