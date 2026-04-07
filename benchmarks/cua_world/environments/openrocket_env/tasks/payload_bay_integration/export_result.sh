#!/bin/bash
# Export script for payload_bay_integration task

echo "=== Exporting payload_bay_integration result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/payload_integrated_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/payload_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime=0
new_md5=""
if [ -f "$ORK_FILE" ]; then
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
    new_md5=$(md5sum "$ORK_FILE" | awk '{print $1}')
fi

report_size=0
if [ -f "$REPORT_FILE" ]; then
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
fi

original_md5=$(cat /tmp/original_md5.txt 2>/dev/null || echo "")
start_time=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"new_md5\": \"$new_md5\",
  \"original_md5\": \"$original_md5\",
  \"task_start_time\": $start_time,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/payload_result.json

echo "=== Export complete ==="