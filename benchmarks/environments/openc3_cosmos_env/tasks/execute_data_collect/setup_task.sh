#!/bin/bash
echo "=== Setting up Execute Data Collect task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready"
fi

# Record initial COLLECTS counter value
echo "Recording initial COLLECTS counter..."
INITIAL_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
echo "Initial COLLECTS: $INITIAL_COLLECTS"
printf '%s' "$INITIAL_COLLECTS" > /tmp/initial_collects

# Record initial COLLECT command count
INITIAL_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial COLLECT command count: $INITIAL_CMD_COUNT"
printf '%s' "$INITIAL_CMD_COUNT" > /tmp/initial_collect_cmd_count

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to the Command Sender tool
echo "Navigating to Command Sender..."
navigate_to_url "$OPENC3_URL/tools/cmdsender"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Execute Data Collect Task Setup Complete ==="
echo ""
echo "Task: Send INST COLLECT command with TYPE=NORMAL, DURATION=5.0, TEMP=0.0"
echo "Then verify COLLECTS counter incremented in Packet Viewer."
echo ""
