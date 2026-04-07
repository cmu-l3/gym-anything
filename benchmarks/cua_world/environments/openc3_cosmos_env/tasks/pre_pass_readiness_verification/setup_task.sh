#!/bin/bash
echo "=== Setting up Pre-Pass Readiness Verification task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST (before recording timestamp)
rm -f /home/ga/Desktop/pre_pass_checklist.json 2>/dev/null || true
rm -f /tmp/pre_pass_readiness_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/pre_pass_start_ts
echo "Task start recorded: $(cat /tmp/pre_pass_start_ts)"

# Disconnect the INST2_INT interface to create the troubleshooting scenario
echo "Disconnecting INST2_INT interface to set up task scenario..."
cosmos_api "disconnect_interface" '"INST2_INT"' 2>/dev/null || true
sleep 3

# Record initial command counts for INST CLEAR and INST COLLECT
INITIAL_CLEAR_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
INITIAL_COLLECT_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

echo "Initial CLEAR count: $INITIAL_CLEAR_COUNT"
echo "Initial COLLECT count: $INITIAL_COLLECT_COUNT"

printf '%s' "$INITIAL_CLEAR_COUNT" > /tmp/pre_pass_initial_clear
printf '%s' "$INITIAL_COLLECT_COUNT" > /tmp/pre_pass_initial_collect

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
take_screenshot /tmp/pre_pass_readiness_start.png

echo "=== Pre-Pass Readiness Verification Setup Complete ==="
echo ""
echo "Task: Diagnose INST2_INT, send CLEAR & COLLECT to INST, and write readiness checklist."
echo "Output must be written to: /home/ga/Desktop/pre_pass_checklist.json"
echo ""