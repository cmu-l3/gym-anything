#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Royalty Reconciliation Result ==="

# Take final screenshot before doing anything
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Try to save the document gracefully
if is_onlyoffice_running; then
    echo "Attempting to save document..."
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 3
    close_onlyoffice ga :1
    sleep 2
fi

# Force kill if still running
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

REPORT_PATH="/home/ga/Documents/Spreadsheets/royalty_statement_Q3.xlsx"
TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo 0)
    OUTPUT_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo 0)
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    echo "Report saved: $REPORT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "Report not found at standard path. Checking for misnamed files..."
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

# Write results
cat > /tmp/task_result.json << JSONEOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "output_exists": $OUTPUT_EXISTS,
  "file_created_during_task": $FILE_MODIFIED,
  "output_size_bytes": $OUTPUT_SIZE,
  "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
JSONEOF

echo "=== Export Complete ==="