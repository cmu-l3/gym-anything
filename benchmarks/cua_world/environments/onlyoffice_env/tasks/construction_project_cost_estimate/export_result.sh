#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Construction Cost Estimate Result ==="

su - ga -c "DISPLAY=:1 import -window root /tmp/construction_project_cost_estimate_final_screenshot.png" || true

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

ESTIMATE_PATH="/home/ga/Documents/Spreadsheets/medical_office_estimate.xlsx"
OUTPUT_PATH="$ESTIMATE_PATH"

if [ -f "$ESTIMATE_PATH" ]; then
    echo "Cost estimate saved: $ESTIMATE_PATH"
    ls -lh "$ESTIMATE_PATH"
else
    echo "Cost estimate not found: $ESTIMATE_PATH"
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

cat > /tmp/construction_project_cost_estimate_result.json << JSONEOF
{
  "task_name": "construction_project_cost_estimate",
  "timestamp": $(date +%s),
  "output_file_exists": $([ -f "$OUTPUT_PATH" ] && echo "true" || echo "false"),
  "output_file_size": $(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
}
JSONEOF

echo "=== Export Complete ==="
