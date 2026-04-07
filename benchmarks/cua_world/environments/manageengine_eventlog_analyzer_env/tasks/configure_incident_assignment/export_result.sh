#!/bin/bash
echo "=== Exporting Configure Incident Assignment Result ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EVIDENCE_FILE="/home/ga/audit_evidence.csv"
SCREENSHOT_FILE="/tmp/rule_configured.png"

# Take final screenshot if agent didn't save one, or purely for state capture
take_screenshot /tmp/task_final.png

# Check Evidence File (Audit Trail)
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
CONTENT_MATCH="false"

if [ -f "$EVIDENCE_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EVIDENCE_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EVIDENCE_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Grep for keywords in the CSV (case insensitive)
    if grep -iq "Critical_Response_Auto" "$EVIDENCE_FILE"; then
        CONTENT_MATCH="true"
    fi
fi

# Check Screenshot Existence (Agent was asked to save it)
AGENT_SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_FILE" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
fi

# Check if ELA is still running
APP_RUNNING=$(pgrep -f "java.*EventLog" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "audit_file_exists": $FILE_EXISTS,
    "audit_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "audit_file_size": $FILE_SIZE,
    "audit_content_match": $CONTENT_MATCH,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png",
    "agent_screenshot_path": "$SCREENSHOT_FILE",
    "audit_file_path": "$EVIDENCE_FILE"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="