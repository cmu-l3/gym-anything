#!/bin/bash
echo "=== Setting up External Stakeholder Dashboard Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST to prevent false positives
rm -f /home/ga/Desktop/stakeholder_dashboard.html 2>/dev/null || true
rm -f /tmp/dashboard_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/dashboard_start_ts
echo "Task start recorded: $(cat /tmp/dashboard_start_ts)"

# Record initial CMD_ACPT_CNT from telemetry
# This is the actual value the agent will read, so we query it via tlm
INITIAL_CMD_CNT=$(cosmos_tlm "INST HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null || echo "0")
if [ -z "$INITIAL_CMD_CNT" ] || [ "$INITIAL_CMD_CNT" = "null" ]; then
    INITIAL_CMD_CNT="0"
fi
echo "Initial CMD_ACPT_CNT: $INITIAL_CMD_CNT"
printf '%s' "$INITIAL_CMD_CNT" > /tmp/dashboard_initial_cmd_cnt

# Seed a limit violation to make the dashboard more interesting (optional)
echo "Injecting a telemetry variation..."
cosmos_api "inject_tlm" '"INST","HEALTH_STATUS",{"TEMP1":93.5}' 2>/dev/null || true
sleep 2

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
take_screenshot /tmp/dashboard_start.png

echo "=== Setup Complete ==="
echo "Output must be written to: /home/ga/Desktop/stakeholder_dashboard.html"
echo ""