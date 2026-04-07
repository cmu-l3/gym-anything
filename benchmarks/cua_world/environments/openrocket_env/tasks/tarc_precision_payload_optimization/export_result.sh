#!/bin/bash
echo "=== Exporting tarc_precision_payload_optimization result ==="
source /workspace/scripts/task_utils.sh || exit 1

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/tarc_competition_design.ork"
REPORT_FILE="/home/ga/Documents/exports/tarc_engineering_notebook.md"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime=0
report_size=0
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

file_created_during_task="false"
if [ "$ork_exists" = "true" ] && [ "$ork_mtime" -gt "$TASK_START" ]; then
    file_created_during_task="true"
fi

# Try to look for .txt as a fallback for the report
if [ "$report_exists" = "false" ] && [ -f "/home/ga/Documents/exports/tarc_engineering_notebook.txt" ]; then
    REPORT_FILE="/home/ga/Documents/exports/tarc_engineering_notebook.txt"
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
fi

# Write result to JSON robustly
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "ork_exists": $ork_exists,
  "ork_mtime": $ork_mtime,
  "file_created_during_task": $file_created_during_task,
  "report_exists": $report_exists,
  "report_size": $report_size
}
EOF

rm -f /tmp/tarc_result.json 2>/dev/null || sudo rm -f /tmp/tarc_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tarc_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tarc_result.json
chmod 666 /tmp/tarc_result.json 2>/dev/null || sudo chmod 666 /tmp/tarc_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="