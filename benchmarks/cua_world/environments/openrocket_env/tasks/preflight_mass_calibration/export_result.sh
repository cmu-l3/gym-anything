#!/bin/bash
echo "=== Exporting preflight_mass_calibration result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/mass_calibration_final.png 2>/dev/null || true

OUTPUT_ORK="/home/ga/Documents/rockets/calibrated_simple_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/mass_properties_report.txt"
GT_FILE="/tmp/mass_calibration_gt.txt"

ork_exists="false"
report_exists="false"
[ -f "$OUTPUT_ORK" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime=0
ork_md5=""
report_size=0
[ -f "$OUTPUT_ORK" ] && ork_mtime=$(stat -c %Y "$OUTPUT_ORK" 2>/dev/null)
[ -f "$OUTPUT_ORK" ] && ork_md5=$(md5sum "$OUTPUT_ORK" | awk '{print $1}')
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

task_start_ts=0
orig_md5=""
if [ -f "$GT_FILE" ]; then
    task_start_ts=$(grep "task_start_ts" "$GT_FILE" | cut -d'=' -f2)
    orig_md5=$(grep "orig_md5" "$GT_FILE" | cut -d'=' -f2)
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"ork_md5\": \"$ork_md5\",
  \"report_exists\": $report_exists,
  \"report_size\": $report_size,
  \"task_start_ts\": $task_start_ts,
  \"orig_md5\": \"$orig_md5\"
}" /tmp/mass_calibration_result.json

echo "=== Export complete ==="