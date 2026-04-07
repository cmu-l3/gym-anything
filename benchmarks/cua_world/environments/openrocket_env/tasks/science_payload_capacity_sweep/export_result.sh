#!/bin/bash
# Export script for science_payload_capacity_sweep task

echo "=== Exporting science_payload_capacity_sweep result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Capture final screenshot
take_screenshot /tmp/payload_sweep_final.png 2>/dev/null || true

CSV_FILE="/home/ga/Documents/exports/payload_curve.csv"
REPORT_FILE="/home/ga/Documents/exports/payload_summary.txt"
FINAL_ORK="/home/ga/Documents/rockets/valetudo_payload_4kg.ork"

csv_exists="false"
report_exists="false"
ork_exists="false"

[ -f "$CSV_FILE" ] && csv_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"
[ -f "$FINAL_ORK" ] && ork_exists="true"

csv_size=0
report_size=0
ork_size=0

[ -f "$CSV_FILE" ] && csv_size=$(stat -c %s "$CSV_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
[ -f "$FINAL_ORK" ] && ork_size=$(stat -c %s "$FINAL_ORK" 2>/dev/null)

# Generate export JSON file for the verifier
write_result_json "{
  \"csv_exists\": $csv_exists,
  \"report_exists\": $report_exists,
  \"ork_exists\": $ork_exists,
  \"csv_size\": $csv_size,
  \"report_size\": $report_size,
  \"ork_size\": $ork_size
}" /tmp/payload_sweep_result.json

echo "=== Export complete ==="