#!/bin/bash
echo "=== Exporting Photo Hunter results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the proof screenshot exists and was created during the task
PROOF_PATH="/home/ga/photo_hunter_success.png"
PROOF_EXISTS="false"
PROOF_CREATED_DURING_TASK="false"
PROOF_SIZE="0"

if [ -f "$PROOF_PATH" ]; then
    PROOF_EXISTS="true"
    PROOF_SIZE=$(stat -c %s "$PROOF_PATH" 2>/dev/null || echo "0")
    PROOF_MTIME=$(stat -c %Y "$PROOF_PATH" 2>/dev/null || echo "0")
    
    if [ "$PROOF_MTIME" -gt "$TASK_START" ]; then
        PROOF_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if GCompris is still running (it should be)
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "proof_screenshot_exists": $PROOF_EXISTS,
    "proof_created_during_task": $PROOF_CREATED_DURING_TASK,
    "proof_size_bytes": $PROOF_SIZE,
    "app_was_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="