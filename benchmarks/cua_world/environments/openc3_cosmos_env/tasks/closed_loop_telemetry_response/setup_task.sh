#!/bin/bash
echo "=== Setting up Closed-Loop Telemetry Response task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST (before recording timestamp) to prevent false positives
rm -f /home/ga/Desktop/closed_loop.py 2>/dev/null || true
rm -f /home/ga/Desktop/automation_report.json 2>/dev/null || true
rm -f /tmp/closed_loop_telemetry_response_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/closed_loop_telemetry_start_ts
echo "Task start recorded: $(cat /tmp/closed_loop_telemetry_start_ts)"

# Record initial COLLECT command count
# The script will send an INST COLLECT command, so we need a baseline to verify execution
INITIAL_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial INST COLLECT command count: $INITIAL_CMD_COUNT"
printf '%s' "$INITIAL_CMD_COUNT" > /tmp/closed_loop_telemetry_initial_cmd_count

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
take_screenshot /tmp/closed_loop_telemetry_start.png

echo "=== Closed-Loop Telemetry Response Setup Complete ==="
echo ""
echo "Task: Write and execute a closed-loop Python script."
echo "Outputs must be written to: /home/ga/Desktop/closed_loop.py and /home/ga/Desktop/automation_report.json"
echo ""