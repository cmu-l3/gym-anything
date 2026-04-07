#!/bin/bash
echo "=== Exporting launch_site_environmental_analysis result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/task_final.png 2>/dev/null || true

# Expected output paths
ORK_FILE="/home/ga/Documents/rockets/environmental_analysis.ork"
SWITZERLAND_CSV="/home/ga/Documents/exports/switzerland.csv"
NEW_MEXICO_CSV="/home/ga/Documents/exports/new_mexico.csv"
REPORT_FILE="/home/ga/Documents/exports/environmental_impact_report.txt"

ork_exists="false"
switz_csv_exists="false"
nm_csv_exists="false"
report_exists="false"

[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$SWITZERLAND_CSV" ] && switz_csv_exists="true"
[ -f "$NEW_MEXICO_CSV" ] && nm_csv_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_size=0
switz_csv_size=0
nm_csv_size=0
report_size=0

[ -f "$ORK_FILE" ] && ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
[ -f "$SWITZERLAND_CSV" ] && switz_csv_size=$(stat -c %s "$SWITZERLAND_CSV" 2>/dev/null)
[ -f "$NEW_MEXICO_CSV" ] && nm_csv_size=$(stat -c %s "$NEW_MEXICO_CSV" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

# Check timestamps relative to task start to prevent spoofing
task_start=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ork_mtime=0
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)

created_during_task="false"
if [ "$ork_mtime" -gt "$task_start" ]; then
    created_during_task="true"
fi

# Write metadata for verifier
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"created_during_task\": $created_during_task,
  \"switz_csv_exists\": $switz_csv_exists,
  \"switz_csv_size\": $switz_csv_size,
  \"nm_csv_exists\": $nm_csv_exists,
  \"nm_csv_size\": $nm_csv_size,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/task_result.json

echo "=== Export complete ==="