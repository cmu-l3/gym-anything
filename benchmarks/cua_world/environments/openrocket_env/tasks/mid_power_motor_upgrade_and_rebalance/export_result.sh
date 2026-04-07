#!/bin/bash
echo "=== Exporting mid_power_motor_upgrade_and_rebalance result ==="

source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot for trajectory verification
take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/mid_power_upscale.ork"
REPORT_FILE="/home/ga/Documents/exports/upscale_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_size=0
report_size=0
[ -f "$ORK_FILE" ] && ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

# Generate export JSON payload
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/task_result.json

echo "=== Export complete ==="