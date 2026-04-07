#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting PCBA Cost Rollup Result ==="

# Record task end time
echo $(date +%s) > /tmp/pcba_cost_rollup_end_ts

# Take final screenshot showing agent's work
DISPLAY=:1 scrot /tmp/pcba_cost_rollup_final_screenshot.png 2>/dev/null || true

# Programmatically close the document, saving it
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure all processes are killed
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

REPORT_PATH="/home/ga/Documents/Spreadsheets/pcba_cost_rollup.xlsx"
OUTPUT_PATH="$REPORT_PATH"

if [ -f "$REPORT_PATH" ]; then
    echo "Workbook saved successfully: $REPORT_PATH"
else
    echo "Workbook not found at expected location: $REPORT_PATH"
    # Fallback checking just in case
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

# Store metadata for verification script
cat > /tmp/pcba_cost_rollup_result.json << JSONEOF
{
  "task_name": "pcba_bom_cost_rollup",
  "start_time": $(cat /tmp/pcba_cost_rollup_start_ts 2>/dev/null || echo 0),
  "end_time": $(cat /tmp/pcba_cost_rollup_end_ts 2>/dev/null || echo 0),
  "output_file_exists": $([ -f "$OUTPUT_PATH" ] && echo "true" || echo "false"),
  "output_file_size": $(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
}
JSONEOF

echo "=== Export Complete ==="