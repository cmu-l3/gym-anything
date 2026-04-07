#!/bin/bash
echo "=== Setting up Interface Recovery Report task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST to prevent false positives
rm -f /home/ga/Desktop/interface_recovery_report.json 2>/dev/null || true
rm -f /tmp/interface_recovery_report_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/interface_recovery_start_ts
echo "Task start recorded: $(cat /tmp/interface_recovery_start_ts)"

# Disconnect the INST_INT interface to simulate the fault
echo "Simulating interface fault (disconnecting INST_INT)..."
cosmos_api "disconnect_interface" '"INST_INT"' 2>/dev/null || true
sleep 3

# Verify it was disconnected
INT_STATE=$(cosmos_api "interface_state" '"INST_INT"' 2>/dev/null | jq -r '.result // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
echo "Initial INST_INT state: $INT_STATE"
printf '%s' "$INT_STATE" > /tmp/interface_recovery_initial_state

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
take_screenshot /tmp/interface_recovery_start.png

echo "=== Interface Recovery Setup Complete ==="
echo ""
echo "Task: Diagnose interface fault, reconnect, verify telemetry, write report."
echo "Output must be written to: /home/ga/Desktop/interface_recovery_report.json"
echo ""