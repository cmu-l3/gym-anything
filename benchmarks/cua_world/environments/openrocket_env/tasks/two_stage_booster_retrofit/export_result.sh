#!/bin/bash
# Export script for two_stage_booster_retrofit task

echo "=== Exporting two_stage_booster_retrofit result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/two_stage_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/two_stage_upgrade.ork"
REPORT_FILE="/home/ga/Documents/exports/staging_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime=0
report_size=0
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

task_start=$(grep task_start_ts /tmp/two_stage_gt.txt 2>/dev/null | cut -d'=' -f2 || echo "0")

# Write results to a JSON file safely
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"task_start_ts\": $task_start,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/two_stage_result.json

echo "=== Export complete ==="