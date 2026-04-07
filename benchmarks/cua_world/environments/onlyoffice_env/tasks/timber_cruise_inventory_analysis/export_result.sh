#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Timber Cruise Inventory Result ==="

su - ga -c "DISPLAY=:1 import -window root /tmp/timber_cruise_final_screenshot.png" || true

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

REPORT_PATH="/home/ga/Documents/Spreadsheets/elk_creek_inventory.xlsx"
OUTPUT_PATH="$REPORT_PATH"

if [ -f "$REPORT_PATH" ]; then
    echo "Inventory workbook saved: $REPORT_PATH"
    ls -lh "$REPORT_PATH"
else
    echo "Inventory workbook not found: $REPORT_PATH"
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

cat > /tmp/timber_cruise_result.json << JSONEOF
{
  "task_name": "timber_cruise_inventory_analysis",
  "timestamp": $(date +%s),
  "output_file_exists": $([ -f "$OUTPUT_PATH" ] && echo "true" || echo "false"),
  "output_file_size": $(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
}
JSONEOF

echo "=== Export Complete ==="