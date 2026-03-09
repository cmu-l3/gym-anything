#!/bin/bash
echo "=== Exporting edit_visitor_record result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/edit_visitor_record_start_time 2>/dev/null || echo "0")

# Paths
EXPECTED_SCREENSHOT="/home/ga/Documents/corrected_visitor_screenshot.png"
FINAL_STATE_SCREENSHOT="/tmp/task_final.png"

# 1. Check if agent's screenshot exists and verify timestamp
AGENT_SCREENSHOT_EXISTS="false"
AGENT_SCREENSHOT_VALID="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Check if created/modified AFTER task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        AGENT_SCREENSHOT_VALID="true"
    fi
    
    # Copy to tmp for easy access by verifier
    cp "$EXPECTED_SCREENSHOT" /tmp/agent_evidence.png
fi

# 2. Capture system final state (backup evidence)
take_screenshot "$FINAL_STATE_SCREENSHOT"

# 3. Check if Lobby Track is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "agent_screenshot_valid": $AGENT_SCREENSHOT_VALID,
    "agent_screenshot_path": "$EXPECTED_SCREENSHOT",
    "app_running": $APP_RUNNING,
    "system_screenshot_path": "$FINAL_STATE_SCREENSHOT"
}
EOF

# Move result to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="