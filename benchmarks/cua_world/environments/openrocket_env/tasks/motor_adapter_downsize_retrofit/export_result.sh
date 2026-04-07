#!/bin/bash
echo "=== Exporting motor adapter downsize retrofit result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

OUTPUT_ORK="/home/ga/Documents/rockets/janus_29mm_adapter.ork"
REPORT_FILE="/home/ga/Documents/exports/adapter_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$OUTPUT_ORK" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime=0
report_size=0
[ -f "$OUTPUT_ORK" ] && ork_mtime=$(stat -c %Y "$OUTPUT_ORK" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/task_result.json

echo "=== Export complete ==="