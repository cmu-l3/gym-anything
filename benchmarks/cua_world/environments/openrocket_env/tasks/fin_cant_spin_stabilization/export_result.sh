#!/bin/bash
# Export script for fin_cant_spin_stabilization task

echo "=== Exporting fin_cant_spin_stabilization result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Capture final state
take_screenshot /tmp/fin_cant_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/spin_stabilized_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/spin_stabilization_report.txt"

ork_exists="false"
report_exists="false"

[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_size=0
report_size=0
ork_mtime=0

if [ "$ork_exists" == "true" ]; then
    ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
fi

if [ "$report_exists" == "true" ]; then
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
fi

# Write metadata for the verifier to consume
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"ork_mtime\": $ork_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/fin_cant_result.json

echo "=== Export complete ==="