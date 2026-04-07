#!/bin/bash
echo "=== Exporting Investigate User Creation Result ==="

source /workspace/scripts/task_utils.sh

REPORT_FILE="/home/ga/incident_findings.json"
GROUND_TRUTH_FILE="/var/lib/wazuh-dashboard/ground_truth.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Agent Report
REPORT_EXISTS="false"
REPORT_CONTENT="{}"
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Validate it is valid JSON
    if jq . "$REPORT_FILE" >/dev/null 2>&1; then
        REPORT_CONTENT=$(cat "$REPORT_FILE")
    fi
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Get Ground Truth
GROUND_TRUTH="{}"
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GROUND_TRUTH=$(cat "$GROUND_TRUTH_FILE")
fi

# 4. Check Application State
FIREFOX_RUNNING="false"
if pgrep -f firefox >/dev/null; then
    FIREFOX_RUNNING="true"
fi

# 5. Assemble Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "firefox_running": $FIREFOX_RUNNING,
    "agent_report": $REPORT_CONTENT,
    "ground_truth": $GROUND_TRUTH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to public location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json