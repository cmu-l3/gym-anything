#!/bin/bash
set -e

echo "=== Exporting digital_logic_circuit results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture system-level final screenshot (ground truth of what's on screen)
take_screenshot /tmp/task_final.png

# 2. Check for the Agent's evidence file
EVIDENCE_PATH="/home/ga/Documents/digital_circuit_success.png"
EVIDENCE_EXISTS="false"
EVIDENCE_VALID="false"
EVIDENCE_SIZE="0"

if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp to ensure it was created DURING the task
    FILE_TIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        EVIDENCE_VALID="true"
    fi
fi

# 3. Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_valid_timestamp": $EVIDENCE_VALID,
    "evidence_size_bytes": $EVIDENCE_SIZE,
    "final_screenshot_path": "/tmp/task_final.png",
    "agent_screenshot_path": "$EVIDENCE_PATH"
}
EOF

# Move result to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"