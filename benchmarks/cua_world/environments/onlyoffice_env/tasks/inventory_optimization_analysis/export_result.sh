#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Inventory Optimization Analysis Result ==="

TASK_START=$(cat /tmp/inventory_optimization_start_ts 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
su - ga -c "DISPLAY=:1 import -window root /tmp/inventory_task_final.png" || true

# Save and close application gracefully if open
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

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/inventory_optimization.xlsx"

FILE_CREATED_DURING_TASK="false"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Workbook saved: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "Workbook not found: $OUTPUT_PATH"
fi

# Export metadata json for verifier
cat > /tmp/inventory_task_result.json << JSONEOF
{
  "task_name": "inventory_optimization_analysis",
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "output_exists": $OUTPUT_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "output_size": $OUTPUT_SIZE
}
JSONEOF

echo "=== Export Complete ==="