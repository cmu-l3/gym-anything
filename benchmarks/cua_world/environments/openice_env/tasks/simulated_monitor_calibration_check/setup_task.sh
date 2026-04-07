#!/bin/bash
echo "=== Setting up Simulated Monitor Calibration Check ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up any previous artifacts
rm -f /home/ga/Desktop/calibration_report.csv 2>/dev/null || true
rm -f /home/ga/Desktop/calibration_120bpm.png 2>/dev/null || true

# Record initial window state
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Record initial log size
LOG_FILE="/home/ga/openice/logs/openice.log"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="