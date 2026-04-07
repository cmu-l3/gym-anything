#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Walleye Stock Assessment Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/walleye_stock_assessment_start_ts 2>/dev/null || echo "0")

# Capture final UI state screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

# Try to save the document using UI interaction before killing
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
    kill_onlyoffice ga
fi

sleep 1

# Check for the expected output file
EXPECTED_OUTPUT="/home/ga/Documents/Spreadsheets/vermilion_walleye_assessment.xlsx"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_OUTPUT" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo 0)
    
    # Check if created/modified during task
    OUTPUT_MTIME=$(stat -c %Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Output file found: $EXPECTED_OUTPUT ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at $EXPECTED_OUTPUT"
    # Check if they saved it somewhere else
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

# Write metadata for verifier
cat > /tmp/walleye_assessment_result.json << JSONEOF
{
  "task_name": "walleye_stock_assessment",
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "output_exists": $FILE_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "output_size_bytes": $FILE_SIZE,
  "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Result JSON saved to /tmp/walleye_assessment_result.json"
echo "=== Export Complete ==="