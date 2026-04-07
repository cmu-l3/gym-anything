#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Urban Gentrification Analysis Result ==="

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

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

REPORT_PATH="/home/ga/Documents/Spreadsheets/austin_gentrification_analysis.xlsx"

OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -f "$REPORT_PATH" ]; then
    echo "Report saved: $REPORT_PATH"
    ls -lh "$REPORT_PATH"
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo 0)
    OUTPUT_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo 0)
else
    echo "Report not found: $REPORT_PATH"
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

cat > /tmp/task_result.json << JSONEOF
{
  "task_name": "urban_gentrification_analysis",
  "task_start": $TASK_START,
  "output_file_exists": $OUTPUT_EXISTS,
  "output_file_size": $OUTPUT_SIZE,
  "output_mtime": $OUTPUT_MTIME
}
JSONEOF

echo "=== Export Complete ==="