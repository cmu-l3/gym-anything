#!/bin/bash
echo "=== Exporting launch_clearance_velocity_optimization result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/task_final_state.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/optimized_rail_clearance.ork"
REPORT_FILE="/home/ga/Documents/exports/clearance_report.txt"
START_TS_FILE="/tmp/task_start_time.txt"

ork_exists="false"
report_exists="false"
file_created_during_task="false"

[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime=0
report_size=0

# Extract task start timestamp to verify the file was actually made by the agent
start_ts=0
if [ -f "$START_TS_FILE" ]; then
    start_ts=$(grep 'task_start_ts=' "$START_TS_FILE" | cut -d'=' -f2)
fi

if [ "$ork_exists" = "true" ]; then
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
    if [ "$ork_mtime" -ge "$start_ts" ]; then
        file_created_during_task="true"
    fi
fi

if [ "$report_exists" = "true" ]; then
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
fi

app_running="false"
if pgrep -f "OpenRocket.jar" > /dev/null; then
    app_running="true"
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"file_created_during_task\": $file_created_during_task,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size,
  \"app_was_running\": $app_running
}" /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="