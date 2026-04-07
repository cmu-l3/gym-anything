#!/bin/bash
# Export script for boattail_drag_reduction_retrofit task

echo "=== Exporting boattail_drag_reduction_retrofit result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/task_final_state.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORK_FILE="/home/ga/Documents/exports/boattail_retrofit.ork"
REPORT_FILE="/home/ga/Documents/exports/boattail_report.txt"

ork_exists="false"
report_exists="false"
ork_created_during_task="false"
report_created_during_task="false"

[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_size=0
report_size=0
ork_mtime=0
report_mtime=0

if [ "$ork_exists" = "true" ]; then
    ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null || echo 0)
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null || echo 0)
    if [ "$ork_mtime" -gt "$TASK_START" ]; then
        ork_created_during_task="true"
    fi
fi

if [ "$report_exists" = "true" ]; then
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo 0)
    report_mtime=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo 0)
    if [ "$report_mtime" -gt "$TASK_START" ]; then
        report_created_during_task="true"
    fi
fi

# Prepare JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_ts": $TASK_START,
  "ork_exists": $ork_exists,
  "ork_created_during_task": $ork_created_during_task,
  "ork_size_bytes": $ork_size,
  "report_exists": $report_exists,
  "report_created_during_task": $report_created_during_task,
  "report_size_bytes": $report_size
}
EOF

# Write result securely
write_result_json "$(cat "$TEMP_JSON")" /tmp/boattail_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="