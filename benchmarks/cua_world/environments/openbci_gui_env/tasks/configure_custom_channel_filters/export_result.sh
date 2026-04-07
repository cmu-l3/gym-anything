#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final system state screenshot (backup evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for the specific screenshot the agent was asked to take
AGENT_SCREENSHOT_PATH="/home/ga/Documents/OpenBCI_GUI/Screenshots/custom_filters.png"
AGENT_SCREENSHOT_EXISTS="false"
AGENT_SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$AGENT_SCREENSHOT_PATH" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$AGENT_SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        AGENT_SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    # Copy to /tmp for easier extraction by verifier
    cp "$AGENT_SCREENSHOT_PATH" /tmp/agent_evidence.png
fi

# 3. Check if OpenBCI is running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 4. Check for Playback log activity (weak signal, but helpful)
# OpenBCI typically logs to console/stdout. We redirected to /tmp/openbci_launch.log
PLAYBACK_ACTIVE="false"
if grep -qi "Playback" /tmp/openbci_launch.log 2>/dev/null; then
    PLAYBACK_ACTIVE="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "agent_screenshot_fresh": $AGENT_SCREENSHOT_CREATED_DURING_TASK,
    "playback_log_detected": $PLAYBACK_ACTIVE,
    "final_screenshot_path": "/tmp/task_final.png",
    "agent_evidence_path": "/tmp/agent_evidence.png"
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"