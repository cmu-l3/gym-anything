#!/bin/bash
echo "=== Exporting network_stress_test_analysis result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Paths
BASELINE_XML="/home/ga/SUMO_Output/baseline_summary.xml"
STRESS_XML="/home/ga/SUMO_Output/stress_summary.xml"
REPORT_TXT="/home/ga/SUMO_Output/stress_test_report.txt"

# Verification Variables
BASELINE_EXISTS="false"
STRESS_EXISTS="false"
REPORT_EXISTS="false"
FILES_CREATED_DURING_TASK="false"

# Check baseline XML
if [ -f "$BASELINE_XML" ]; then
    BASELINE_EXISTS="true"
    BASELINE_MTIME=$(stat -c %Y "$BASELINE_XML" 2>/dev/null || echo "0")
    cp "$BASELINE_XML" /tmp/baseline_summary.xml
    chmod 666 /tmp/baseline_summary.xml
fi

# Check stress XML
if [ -f "$STRESS_XML" ]; then
    STRESS_EXISTS="true"
    STRESS_MTIME=$(stat -c %Y "$STRESS_XML" 2>/dev/null || echo "0")
    cp "$STRESS_XML" /tmp/stress_summary.xml
    chmod 666 /tmp/stress_summary.xml
fi

# Check report TXT
if [ -f "$REPORT_TXT" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_TXT" 2>/dev/null || echo "0")
    cp "$REPORT_TXT" /tmp/stress_test_report.txt
    chmod 666 /tmp/stress_test_report.txt
fi

# Verify timestamps to prevent gaming
if [ "$BASELINE_EXISTS" = "true" ] && [ "$STRESS_EXISTS" = "true" ] && [ "$REPORT_EXISTS" = "true" ]; then
    if [ "$BASELINE_MTIME" -gt "$TASK_START" ] && [ "$STRESS_MTIME" -gt "$TASK_START" ] && [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Write metadata JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "baseline_exists": $BASELINE_EXISTS,
    "stress_exists": $STRESS_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "files_created_during_task": $FILES_CREATED_DURING_TASK
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="