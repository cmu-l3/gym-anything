#!/bin/bash
echo "=== Setting up Monitor Thermal Alarm task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready"
fi

# Record initial state - capture current TEMP1 value
echo "Recording initial telemetry state..."
INITIAL_TEMP1=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "unknown")
echo "Initial TEMP1: $INITIAL_TEMP1"
printf '%s' "$INITIAL_TEMP1" > /tmp/initial_temp1

# Record initial command count
INITIAL_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial CLEAR command count: $INITIAL_CMD_COUNT"
printf '%s' "$INITIAL_CMD_COUNT" > /tmp/initial_clear_cmd_count

# Ensure Firefox is running and focused
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

# Navigate to the Limits Monitor tool
echo "Navigating to Limits Monitor..."
navigate_to_url "$OPENC3_URL/tools/limitsmonitor"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Monitor Thermal Alarm Task Setup Complete ==="
echo ""
echo "Task: Monitor satellite thermal telemetry in Limits Monitor."
echo "When you see a temperature limit violation, navigate to"
echo "Command Sender and send the INST CLEAR command."
echo ""
