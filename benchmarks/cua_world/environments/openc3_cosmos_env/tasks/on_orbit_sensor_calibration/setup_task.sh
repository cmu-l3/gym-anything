#!/bin/bash
echo "=== Setting up On-Orbit Sensor Calibration task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST to prevent false positives
rm -f /home/ga/Desktop/calibration_offsets.json 2>/dev/null || true
rm -f /tmp/on_orbit_sensor_calibration_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/on_orbit_sensor_calibration_start_ts
echo "Task start recorded: $(cat /tmp/on_orbit_sensor_calibration_start_ts)"

# Record initial CLEAR command count
INITIAL_CLEAR_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial CLEAR command count: $INITIAL_CLEAR_COUNT"
printf '%s' "$INITIAL_CLEAR_COUNT" > /tmp/on_orbit_sensor_calibration_initial_clear_count

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
take_screenshot /tmp/on_orbit_sensor_calibration_start.png

echo "=== On-Orbit Sensor Calibration Setup Complete ==="
echo ""
echo "Task: Author and execute a Python script to compute sensor calibration offsets."
echo "Output must be written to: /home/ga/Desktop/calibration_offsets.json"
echo ""