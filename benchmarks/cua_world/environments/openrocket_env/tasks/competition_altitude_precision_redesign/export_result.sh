#!/bin/bash
# Export result script for competition_altitude_precision_redesign task
#
# Collects file existence, sizes, and timestamps into a JSON payload
# for the verifier. The verifier fetches actual file content via copy_from_env.

echo "=== Exporting competition_altitude_precision_redesign result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Capture final visual state
take_screenshot /tmp/competition_redesign_final.png 2>/dev/null || true

# Define expected output paths
ORK_FILE="/home/ga/Documents/rockets/competition_final.ork"
CSV_FILE="/home/ga/Documents/exports/flight_data.csv"
REPORT_FILE="/home/ga/Documents/exports/design_report.txt"

# Read task start timestamp
TASK_START_TS=$(grep "task_start_ts" /tmp/competition_redesign_gt.txt 2>/dev/null | cut -d'=' -f2 || echo "0")
START_MD5=$(cat /tmp/competition_redesign_start_md5.txt 2>/dev/null || echo "")

# Check .ork output file
ork_exists="false"
ork_size=0
ork_mtime=0
ork_md5=""
if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
    ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null || echo "0")
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null || echo "0")
    ork_md5=$(file_md5 "$ORK_FILE")
fi

# Check CSV export file
csv_exists="false"
csv_size=0
if [ -f "$CSV_FILE" ]; then
    csv_exists="true"
    csv_size=$(stat -c %s "$CSV_FILE" 2>/dev/null || echo "0")
fi

# Check report file
report_exists="false"
report_size=0
if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# Check if OpenRocket is still running
app_running="false"
if pgrep -f "OpenRocket.jar" > /dev/null; then
    app_running="true"
fi

# Write result JSON
write_result_json "{
  \"task_start_ts\": $TASK_START_TS,
  \"start_ork_md5\": \"$START_MD5\",
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"ork_mtime\": $ork_mtime,
  \"ork_md5\": \"$ork_md5\",
  \"csv_exists\": $csv_exists,
  \"csv_size\": $csv_size,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size,
  \"app_running\": $app_running
}" /tmp/competition_redesign_result.json

echo "=== Export complete ==="
