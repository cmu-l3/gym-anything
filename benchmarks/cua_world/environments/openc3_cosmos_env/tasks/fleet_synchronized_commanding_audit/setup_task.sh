#!/bin/bash
echo "=== Setting up Fleet Synchronized Commanding Audit task ==="

source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST (before recording timestamp) to prevent false positives
rm -f /home/ga/Desktop/fleet_command_report.json 2>/dev/null || true
rm -f /tmp/fleet_command_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/fleet_command_start_ts
echo "Task start recorded: $(cat /tmp/fleet_command_start_ts)"

# Record initial command acceptance counts
# This gives the baseline so the verifier knows if commands were actually sent during the task
INITIAL_INST=$(cosmos_tlm "INST HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null || echo "0")
INITIAL_INST2=$(cosmos_tlm "INST2 HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null || echo "0")

echo "Initial INST CMD_ACPT_CNT: $INITIAL_INST"
echo "Initial INST2 CMD_ACPT_CNT: $INITIAL_INST2"
printf '%s' "$INITIAL_INST" > /tmp/fleet_command_initial_inst
printf '%s' "$INITIAL_INST2" > /tmp/fleet_command_initial_inst2

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
take_screenshot /tmp/fleet_command_start.png

echo "=== Setup Complete ==="
echo ""
echo "Task: Synchronized Fleet Command Audit."
echo "Output must be written to: /home/ga/Desktop/fleet_command_report.json"
echo ""