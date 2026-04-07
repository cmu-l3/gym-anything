#!/bin/bash
echo "=== Setting up CCHD Screening Configuration task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size to only analyze new log entries later
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log file exists
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window to be ready
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial window count
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Clean up any previous run artifacts
rm -f /home/ga/Desktop/cchd_screen_evidence.png 2>/dev/null || true
rm -f /home/ga/Desktop/cchd_device_map.txt 2>/dev/null || true

# Take initial screenshot of the clean state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Initial Log Size: $LOG_SIZE"
echo "Initial Window Count: $INITIAL_WINDOWS"