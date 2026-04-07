#!/bin/bash
echo "=== Exporting mass_audit_ballast_optimization result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/mass_audit_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/mass_audit_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/mass_budget_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_hash=""
report_size=0
[ -f "$ORK_FILE" ] && ork_hash=$(md5sum "$ORK_FILE" | awk '{print $1}')
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_hash\": \"$ork_hash\",
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/mass_audit_result.json

echo "=== Export complete ==="