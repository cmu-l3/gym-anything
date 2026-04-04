#!/bin/bash
set -e
echo "=== Exporting customize_field_labels result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final system screenshot
take_screenshot /tmp/task_final.png

# Check for agent's evidence screenshot
EVIDENCE_PATH="/home/ga/Desktop/escort_label_verification.png"
EVIDENCE_EXISTS="false"
EVIDENCE_CREATED_DURING_TASK="false"

if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING_TASK="true"
    fi
    # Copy evidence to /tmp for extraction
    cp "$EVIDENCE_PATH" /tmp/agent_evidence.png
else
    # If agent didn't save it, use the final screenshot as fallback for VLM
    cp /tmp/task_final.png /tmp/agent_evidence.png 2>/dev/null || true
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_created_during_task": $EVIDENCE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "evidence_path": "/tmp/agent_evidence.png",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result JSON created:"
cat /tmp/task_result.json
echo "=== Export complete ==="