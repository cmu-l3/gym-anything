#!/bin/bash
echo "=== Setting up Simulated Transient Anomaly task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST (before recording timestamp) to prevent false positives
rm -f /home/ga/Desktop/simulated_anomaly_report.json 2>/dev/null || true
rm -f /tmp/simulated_transient_anomaly_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/simulated_transient_anomaly_start_ts
echo "Task start recorded: $(cat /tmp/simulated_transient_anomaly_start_ts)"

# Record initial CLEAR command count
INITIAL_CLEAR_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial CLEAR command count: $INITIAL_CLEAR_COUNT"
printf '%s' "$INITIAL_CLEAR_COUNT" > /tmp/simulated_transient_anomaly_initial_clear

# Record initial YELLOW_HIGH limit for INST HEALTH_STATUS TEMP1
# get_limits returns [RED_LOW, YELLOW_LOW, YELLOW_HIGH, RED_HIGH, GREEN_LOW, GREEN_HIGH]
LIMITS_JSON=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP1"' 2>/dev/null)
INITIAL_YELLOW_HIGH=$(echo "$LIMITS_JSON" | jq -r '.result[2] // "null"' 2>/dev/null || echo "null")
echo "Initial YELLOW_HIGH limit: $INITIAL_YELLOW_HIGH"
printf '%s' "$INITIAL_YELLOW_HIGH" > /tmp/simulated_transient_anomaly_initial_limit

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

# Take initial screenshot
take_screenshot /tmp/simulated_transient_anomaly_start.png

echo "=== Simulated Transient Anomaly Setup Complete ==="
echo ""
echo "Task: Induce an anomaly by overwriting limits, monitor, clean up, and document."
echo "Output must be written to: /home/ga/Desktop/simulated_anomaly_report.json"
echo ""