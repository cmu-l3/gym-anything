#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Urban Street Tree Audit Result ==="

# Take final screenshot
su - ga -c "DISPLAY=:1 import -window root /tmp/urban_street_tree_audit_final_screenshot.png" || true

# Save and close if running
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

REPORT_PATH="/home/ga/Documents/Spreadsheets/tree_maintenance_audit.xlsx"

if [ -f "$REPORT_PATH" ]; then
    echo "Audit workbook saved: $REPORT_PATH"
    ls -lh "$REPORT_PATH"
else
    echo "Audit workbook not found: $REPORT_PATH"
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
fi

cat > /tmp/urban_street_tree_audit_result.json << JSONEOF
{
  "task_name": "urban_street_tree_audit",
  "timestamp": $(date +%s),
  "output_file_exists": $([ -f "$REPORT_PATH" ] && echo "true" || echo "false"),
  "output_file_size": $(stat -c%s "$REPORT_PATH" 2>/dev/null || echo 0)
}
JSONEOF

echo "=== Export Complete ==="