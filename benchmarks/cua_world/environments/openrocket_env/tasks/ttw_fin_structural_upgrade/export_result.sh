#!/bin/bash
echo "=== Exporting ttw_fin_structural_upgrade result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/ttw_upgrade_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/ttw_fin_upgrade.ork"
REPORT_FILE="/home/ga/Documents/exports/ttw_upgrade_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime="0"
report_mtime="0"
report_size=0
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_mtime=$(stat -c %Y "$REPORT_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

TASK_START=$(cat /tmp/ttw_upgrade_gt.txt | grep task_start_ts | cut -d'=' -f2 2>/dev/null || echo "0")

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"report_exists\": $report_exists,
  \"report_mtime\": $report_mtime,
  \"report_size\": $report_size,
  \"task_start\": $TASK_START
}" /tmp/ttw_upgrade_result.json

echo "=== Export complete ==="