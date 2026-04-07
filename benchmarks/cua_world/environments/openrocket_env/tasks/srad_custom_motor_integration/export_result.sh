#!/bin/bash
# Export script for srad_custom_motor_integration task

echo "=== Exporting srad_custom_motor_integration result ==="
source /workspace/scripts/task_utils.sh || exit 1

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_final_state.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/srad_simulated_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/srad_flight_report.txt"

ork_exists="false"
report_exists="false"
ork_created_during_task="false"
report_created_during_task="false"
ork_size=0
report_size=0

if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
    ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
    if [ "$ork_mtime" -ge "$TASK_START" ]; then
        ork_created_during_task="true"
    fi
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
    report_mtime=$(stat -c %Y "$REPORT_FILE" 2>/dev/null)
    if [ "$report_mtime" -ge "$TASK_START" ]; then
        report_created_during_task="true"
    fi
fi

# Check if application was running
app_running=$(pgrep -f "OpenRocket.jar" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/srad_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_was_running": $app_running,
  "ork_exists": $ork_exists,
  "ork_created_during_task": $ork_created_during_task,
  "ork_size": $ork_size,
  "report_exists": $report_exists,
  "report_created_during_task": $report_created_during_task,
  "report_size": $report_size
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="