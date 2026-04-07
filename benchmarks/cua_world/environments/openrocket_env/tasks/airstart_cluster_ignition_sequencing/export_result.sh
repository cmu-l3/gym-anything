#!/bin/bash
echo "=== Exporting airstart_cluster_ignition_sequencing result ==="

source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/task_final.png 2>/dev/null || true

TARGET_ORK="/home/ga/Documents/rockets/airstart_cluster.ork"
CSV_FILE="/home/ga/Documents/exports/airstart_flight_data.csv"
REPORT_FILE="/home/ga/Documents/exports/airstart_report.txt"

ork_exists="false"
csv_exists="false"
report_exists="false"

[ -f "$TARGET_ORK" ] && ork_exists="true"
[ -f "$CSV_FILE" ] && csv_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

csv_size=0
report_size=0
[ -f "$CSV_FILE" ] && csv_size=$(stat -c %s "$CSV_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

APP_RUNNING="false"
if pgrep -f "OpenRocket.jar" > /dev/null; then
    APP_RUNNING="true"
fi

# Write output as JSON into a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "ork_exists": $ork_exists,
  "csv_exists": $csv_exists,
  "csv_size": $csv_size,
  "report_exists": $report_exists,
  "report_size": $report_size,
  "app_running": $APP_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="