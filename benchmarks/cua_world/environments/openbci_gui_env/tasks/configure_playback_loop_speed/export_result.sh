#!/bin/bash
echo "=== Exporting Configure Playback Speed results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/playback_review_config.png"
FINAL_EVIDENCE="/tmp/task_final.png"

# Check agent's screenshot
AGENT_SCREENSHOT_EXISTS="false"
AGENT_SCREENSHOT_TIME="0"
if [ -f "$EXPECTED_SCREENSHOT" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    AGENT_SCREENSHOT_TIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Verify it was created *during* the task
    if [ "$AGENT_SCREENSHOT_TIME" -lt "$TASK_START" ]; then
        echo "WARNING: Agent screenshot is stale (created before task start)."
        AGENT_SCREENSHOT_EXISTS="false"
    fi
fi

# Check if application is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# Take framework's final screenshot (independent verification)
DISPLAY=:1 scrot "$FINAL_EVIDENCE" 2>/dev/null || true

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "agent_screenshot_path": "$EXPECTED_SCREENSHOT",
    "app_was_running": $APP_RUNNING,
    "final_evidence_path": "$FINAL_EVIDENCE"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"