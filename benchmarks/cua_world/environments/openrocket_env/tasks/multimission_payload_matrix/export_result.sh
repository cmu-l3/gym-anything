#!/bin/bash
echo "=== Exporting multimission_payload_matrix result ==="
source /workspace/scripts/task_utils.sh || exit 1

TASK_START=$(grep "task_start_ts" /tmp/multimission_gt.txt | cut -d'=' -f2 || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/multimission_payload.ork"
REPORT_FILE="/home/ga/Documents/exports/mission_matrix_report.txt"

ork_exists="false"
report_exists="false"
ork_created_during_task="false"
report_created_during_task="false"

if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
    mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null || echo "0")
    if [ "$mtime" -ge "$TASK_START" ]; then
        ork_created_during_task="true"
    fi
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
    mtime=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$mtime" -ge "$TASK_START" ]; then
        report_created_during_task="true"
    fi
fi

ork_size=0
report_size=0
[ "$ork_exists" = "true" ] && ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
[ "$report_exists" = "true" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

APP_RUNNING=$(pgrep -f "OpenRocket.jar" > /dev/null && echo "true" || echo "false")

# Save JSON using temp file safety
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_was_running": $APP_RUNNING,
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