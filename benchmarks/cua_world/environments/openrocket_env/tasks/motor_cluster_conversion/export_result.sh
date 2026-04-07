#!/bin/bash
echo "=== Exporting motor_cluster_conversion result ==="

source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/cluster_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/cluster_conversion.ork"
REPORT_FILE="/home/ga/Documents/exports/cluster_report.txt"

ork_exists="false"
report_exists="false"
ork_md5=""
ork_mtime="0"
report_size=0

if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
    ork_md5=$(md5sum "$ORK_FILE" | awk '{print $1}')
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
fi

# Read base MD5 for comparison
BASE_MD5=$(grep "base_md5=" /tmp/cluster_gt.txt | cut -d'=' -f2)
TASK_START=$(grep "task_start_ts=" /tmp/cluster_gt.txt | cut -d'=' -f2)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_md5\": \"$ork_md5\",
  \"base_md5\": \"$BASE_MD5\",
  \"ork_mtime\": $ork_mtime,
  \"task_start\": $TASK_START,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/cluster_result.json

echo "=== Export complete ==="