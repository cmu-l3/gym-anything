#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Highway Earthwork Volume Analysis Result ==="

su - ga -c "DISPLAY=:1 import -window root /tmp/highway_earthwork_volume_analysis_final_screenshot.png" || true

if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    # Send save shortcut safely
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

REPORT_PATH="/home/ga/Documents/Spreadsheets/sr99_mass_haul.xlsx"
OUTPUT_PATH="$REPORT_PATH"

if [ -f "$REPORT_PATH" ]; then
    echo "Mass haul workbook saved: $REPORT_PATH"
    ls -lh "$REPORT_PATH"
else
    echo "Mass haul workbook not found: $REPORT_PATH"
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

cat > /tmp/task_result.json << JSONEOF
{
  "task_name": "highway_earthwork_volume_analysis",
  "timestamp": $(date +%s),
  "output_file_exists": $([ -f "$OUTPUT_PATH" ] && echo "true" || echo "false"),
  "output_file_size": $(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
}
JSONEOF

echo "=== Export Complete ==="