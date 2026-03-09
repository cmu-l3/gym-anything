#!/bin/bash
echo "=== Exporting Crane Puzzle Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check for Agent's Screenshot
AGENT_SCREENSHOT="/home/ga/crane_completion.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$AGENT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$AGENT_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$AGENT_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    # Copy to tmp for export/verification permissions
    cp "$AGENT_SCREENSHOT" /tmp/agent_completion_proof.png
    chmod 666 /tmp/agent_completion_proof.png
fi

# 2. Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Take Final System Screenshot (for VLM verification of state if agent failed to save file)
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "agent_screenshot_size": $SCREENSHOT_SIZE,
    "app_running": $APP_RUNNING,
    "system_final_screenshot": "/tmp/task_final.png",
    "agent_proof_path": "/tmp/agent_completion_proof.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="