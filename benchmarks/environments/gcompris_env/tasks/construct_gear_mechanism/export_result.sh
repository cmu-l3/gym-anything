#!/bin/bash
echo "=== Exporting Construct Gear Mechanism Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the agent created the evidence screenshot
EVIDENCE_PATH="/home/ga/gears_success.png"
EVIDENCE_EXISTS="false"
EVIDENCE_CREATED_DURING_TASK="false"
EVIDENCE_SIZE="0"

if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if GCompris is still running (crashed app = fail)
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# 3. Capture the final system state (independent of agent's screenshot)
# This is what the VLM will verify against for "truth"
take_screenshot /tmp/task_final.png

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_created_during_task": $EVIDENCE_CREATED_DURING_TASK,
    "evidence_size_bytes": $EVIDENCE_SIZE,
    "app_was_running": $APP_RUNNING,
    "system_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="