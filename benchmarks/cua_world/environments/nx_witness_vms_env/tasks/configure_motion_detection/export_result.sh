#!/bin/bash
echo "=== Exporting configure_motion_detection results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Refresh token to ensure we can query the API
refresh_nx_token > /dev/null

# ==============================================================================
# CAPTURE ACTUAL SYSTEM STATE
# ==============================================================================
# We query the API to see what the agent actually changed.
# We save the full JSON response to be parsed by the verifier.
echo "Querying final camera states..."
get_all_cameras > /tmp/system_state.json

# ==============================================================================
# CAPTURE AGENT REPORT
# ==============================================================================
AGENT_REPORT_PATH="/home/ga/motion_detection_config.json"
REPORT_EXISTS="false"
REPORT_VALID="false"

if [ -f "$AGENT_REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Copy to temp location for verifier
    cp "$AGENT_REPORT_PATH" /tmp/agent_report.json
    
    # Check modification time
    REPORT_MTIME=$(stat -c %Y "$AGENT_REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    FILE_CREATED_DURING_TASK="false"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a summary JSON for the basic checks
# (The heavy lifting of JSON parsing happens in verifier.py)
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "system_state_path": "/tmp/system_state.json",
    "agent_report_path": "/tmp/agent_report.json"
}
EOF

echo "Export complete. Result summary saved to /tmp/task_result.json"