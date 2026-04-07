#!/bin/bash
echo "=== Exporting ejection_delay_tuning result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/ejection_delay_final.png 2>/dev/null || true

FIXED_ORK="/home/ga/Documents/rockets/zipper_prevention_fixed.ork"
ORIG_ORK="/home/ga/Documents/rockets/zipper_prevention.ork"
REPORT_FILE="/home/ga/Documents/exports/delay_report.txt"

ork_exists="false"
ork_path=""
report_exists="false"

if [ -f "$FIXED_ORK" ]; then
    ork_exists="true"
    ork_path="$FIXED_ORK"
elif [ -f "$ORIG_ORK" ]; then
    ork_exists="true"
    ork_path="$ORIG_ORK"
fi

[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime="0"
report_size=0
[ "$ork_exists" = "true" ] && ork_mtime=$(stat -c %Y "$ork_path" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_path\": \"$ork_path\",
  \"ork_mtime\": \"$ork_mtime\",
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/ejection_delay_result.json

echo "=== Export complete ==="