#!/bin/bash
echo "=== Setting up Composite Health Index Computation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files to prevent false positives
rm -f /home/ga/Desktop/health_index_report.json 2>/dev/null || true
rm -f /tmp/health_index_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/health_index_start_ts
echo "Task start recorded: $(cat /tmp/health_index_start_ts)"

# Record initial COLLECTS value for boundary verification
INITIAL_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
# If empty or fails, default to 0
if [ -z "$INITIAL_COLLECTS" ] || [ "$INITIAL_COLLECTS" = "null" ]; then
    INITIAL_COLLECTS="0"
fi
echo "Initial COLLECTS counter: $INITIAL_COLLECTS"
printf '%s' "$INITIAL_COLLECTS" > /tmp/health_index_initial_collects

# Force a telemetry state that exercises the algorithm
# We'll set TEMP1 very high and TEMP3 very low so penalties naturally apply
echo "Seeding thermal states to test algorithm penalties..."
cosmos_api "inject_tlm" '"INST","HEALTH_STATUS",{"TEMP1":92.5,"TEMP3":10.2}' 2>/dev/null || true
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
take_screenshot /tmp/health_index_start.png

echo "=== Setup Complete ==="
echo "Output must be written to: /home/ga/Desktop/health_index_report.json"