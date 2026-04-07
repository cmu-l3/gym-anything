#!/bin/bash
echo "=== Exporting hunt_ssh_bruteforce results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/threat_hunt_report.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check report existence and timestamps
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Check bash history for evidence of curl/API usage
# (Note: This is heuristic, agent might delete history, but good for scoring)
HISTORY_EVIDENCE="false"
if grep -q "curl.*9200" /home/ga/.bash_history 2>/dev/null; then
    HISTORY_EVIDENCE="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size": $REPORT_SIZE,
    "history_evidence_found": $HISTORY_EVIDENCE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# If report exists, append its content to a separate file to be read by verifier
if [ "$REPORT_EXISTS" = "true" ]; then
    cp "$REPORT_PATH" /tmp/exported_report.json 2>/dev/null || true
    chmod 644 /tmp/exported_report.json 2>/dev/null || true
fi

# Move result JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported."