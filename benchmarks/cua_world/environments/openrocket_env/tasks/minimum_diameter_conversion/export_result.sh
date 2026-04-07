#!/bin/bash
echo "=== Exporting minimum_diameter_conversion result ==="

source /workspace/scripts/task_utils.sh || exit 1

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/minimum_diameter.ork"
REPORT_FILE="/home/ga/Documents/exports/min_diameter_report.txt"

ork_exists="false"
report_exists="false"
file_created_during_task="false"

if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
    ORK_MTIME=$(stat -c %Y "$ORK_FILE" 2>/dev/null || echo "0")
    if [ "$ORK_MTIME" -gt "$TASK_START" ]; then
        file_created_during_task="true"
    fi
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
else
    report_size=0
fi

# Write results to JSON format safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "ork_exists": $ork_exists,
  "report_exists": $report_exists,
  "file_created_during_task": $file_created_during_task,
  "report_size": $report_size
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export JSON saved"
cat /tmp/task_result.json
echo "=== Export complete ==="