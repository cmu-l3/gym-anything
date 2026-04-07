#!/bin/bash
echo "=== Exporting subcaliber_motor_adapter_retrofit result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Capture final state screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/adapted_dual_deploy.ork"
REPORT_FILE="/home/ga/Documents/exports/adapter_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_size=0
report_size=0
ork_mtime=0
report_mtime=0

[ -f "$ORK_FILE" ] && { ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null); ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null); }
[ -f "$REPORT_FILE" ] && { report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null); report_mtime=$(stat -c %Y "$REPORT_FILE" 2>/dev/null); }

baseline_rings=$(cat /tmp/baseline_rings.txt 2>/dev/null || echo "2")
task_start=$(cat /tmp/task_start_ts.txt 2>/dev/null || echo "0")

# Write payload to JSON for the verifier to consume
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"ork_mtime\": $ork_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size,
  \"report_mtime\": $report_mtime,
  \"baseline_rings\": $baseline_rings,
  \"task_start\": $task_start
}" /tmp/task_result.json

echo "=== Export complete ==="