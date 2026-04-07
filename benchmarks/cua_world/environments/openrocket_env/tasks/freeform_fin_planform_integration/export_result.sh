#!/bin/bash
echo "=== Exporting freeform_fin_planform_integration result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Capture final visual state
take_screenshot /tmp/fin_integration_final.png 2>/dev/null || true

TARGET_ORK="/home/ga/Documents/rockets/freeform_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/fin_integration_report.txt"

ork_exists="false"
report_exists="false"
ork_mtime="0"
report_size="0"

if [ -f "$TARGET_ORK" ]; then
    ork_exists="true"
    ork_mtime=$(stat -c %Y "$TARGET_ORK" 2>/dev/null || echo "0")
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": \"$ork_mtime\",
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/fin_integration_result.json

echo "=== Export complete ==="