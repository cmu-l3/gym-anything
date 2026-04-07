#!/bin/bash
set -euo pipefail

echo "=== Exporting Library Collection Turnover Result ==="

source /workspace/scripts/task_utils.sh

# Record task end timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")

# Capture final screenshot of the agent's workspace before closing
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if application is running and gracefully close it
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    # We do NOT force a save here. Agent must have explicitly saved the correct file name.
    sleep 1
    kill_onlyoffice ga
fi
sleep 1

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/library_collection_analysis.xlsx"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Workbook saved: $OUTPUT_PATH (Size: $OUTPUT_SIZE bytes)"
else
    echo "Workbook not found: $OUTPUT_PATH"
fi

# Package all metadata into JSON
cat > /tmp/task_result.json << JSONEOF
{
  "task_name": "library_collection_turnover",
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "output_file_exists": $OUTPUT_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "output_file_size": $OUTPUT_SIZE
}
JSONEOF

# Ensure permissions so verifier can read files via copy_from_env
chmod 666 /tmp/task_result.json /tmp/ground_truth.json 2>/dev/null || true

echo "=== Export Complete ==="