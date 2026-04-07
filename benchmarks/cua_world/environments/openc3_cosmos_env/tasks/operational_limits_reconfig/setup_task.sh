#!/bin/bash
echo "=== Setting up Operational Limits Reconfig task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST (before recording timestamp)
rm -f /home/ga/Desktop/limits_change_report.json 2>/dev/null || true
rm -f /tmp/operational_limits_reconfig_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/task_start_ts
echo "Task start recorded: $(cat /tmp/task_start_ts)"

# Capture initial limits via COSMOS JSON-RPC API
# get_limits returns [red_low, yellow_low, yellow_high, red_high, green_low, green_high]
INITIAL_LIMITS=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP1"' 2>/dev/null | jq -c '.result // []' 2>/dev/null || echo "[]")
echo "Initial TEMP1 limits: $INITIAL_LIMITS"
echo "$INITIAL_LIMITS" > /tmp/initial_limits.json

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

# Navigate to COSMOS home
echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Operational Limits Reconfig Setup Complete ==="
echo ""
echo "Task: Reconfigure INST TEMP1 limits and document the change."
echo "Output must be written to: /home/ga/Desktop/limits_change_report.json"
echo ""