#!/bin/bash
echo "=== Setting up Diagnose Anomaly task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready"
fi

# Record initial state
echo "Recording initial telemetry state..."
INITIAL_TEMP1=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "unknown")
INITIAL_TEMP2=$(cosmos_tlm "INST HEALTH_STATUS TEMP2" 2>/dev/null || echo "unknown")
INITIAL_TEMP3=$(cosmos_tlm "INST HEALTH_STATUS TEMP3" 2>/dev/null || echo "unknown")
INITIAL_TEMP4=$(cosmos_tlm "INST HEALTH_STATUS TEMP4" 2>/dev/null || echo "unknown")
echo "Initial temperatures: TEMP1=$INITIAL_TEMP1, TEMP2=$INITIAL_TEMP2, TEMP3=$INITIAL_TEMP3, TEMP4=$INITIAL_TEMP4"

# Save initial state
cat > /tmp/initial_anomaly_state.json << EOF
{
  "temp1": "$INITIAL_TEMP1",
  "temp2": "$INITIAL_TEMP2",
  "temp3": "$INITIAL_TEMP3",
  "temp4": "$INITIAL_TEMP4"
}
EOF

# Record initial CLEAR command count
INITIAL_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
printf '%s' "$INITIAL_CMD_COUNT" > /tmp/initial_clear_cmd_count_anomaly

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

# Navigate to the Limits Monitor tool (starting point for anomaly investigation)
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

echo "=== Diagnose Anomaly Task Setup Complete ==="
echo ""
echo "Task: Investigate telemetry limit violations in the Limits Monitor,"
echo "graph the trend in Telemetry Grapher, then send corrective commands."
echo ""
