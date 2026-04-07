#!/bin/bash
echo "=== Setting up Target Telemetry Microservice task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Record task start timestamp
date +%s > /tmp/task_start_time.txt
echo "Task start recorded: $(cat /tmp/task_start_time.txt)"

# Ensure port 8000 is free (kill any leftover processes from previous runs)
echo "Ensuring port 8000 is clear..."
fuser -k 8000/tcp 2>/dev/null || true

# Remove old files to prevent false positives
rm -f /home/ga/Desktop/telemetry_service.py 2>/dev/null || true
rm -f /tmp/microservice_test_result.json 2>/dev/null || true

# Seed some initial activity
cosmos_cmd "INST COLLECT with TYPE NORMAL, DURATION 2.0" 2>/dev/null || true
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
take_screenshot /tmp/task_initial.png

echo "=== Target Telemetry Microservice Setup Complete ==="
echo "Task: Deploy a Python HTTP microservice on port 8000."
echo "Route: GET /api/inst/status"