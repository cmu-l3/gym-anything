#!/bin/bash
echo "=== Exporting collect_webrtc_logs results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Log File
LOG_FILE="/home/ga/jitsi_debug.log"
LOG_EXISTS="false"
LOG_CREATED_DURING_TASK="false"
LOG_SIZE="0"

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
    LOG_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")
    
    if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
        LOG_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Agent-Created Screenshot
EVIDENCE_SCREENSHOT="/home/ga/console_evidence.png"
EVIDENCE_EXISTS="false"
EVIDENCE_CREATED_DURING_TASK="false"

if [ -f "$EVIDENCE_SCREENSHOT" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if Firefox is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Take final system screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "log_file_exists": $LOG_EXISTS,
    "log_file_created_during_task": $LOG_CREATED_DURING_TASK,
    "log_file_size": $LOG_SIZE,
    "evidence_screenshot_exists": $EVIDENCE_EXISTS,
    "evidence_created_during_task": $EVIDENCE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "system_screenshot_path": "/tmp/task_final.png",
    "log_file_path": "$LOG_FILE",
    "evidence_screenshot_path": "$EVIDENCE_SCREENSHOT"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="