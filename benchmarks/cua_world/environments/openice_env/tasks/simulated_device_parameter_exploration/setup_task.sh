#!/bin/bash
echo "=== Setting up Simulated Device Parameter Exploration Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size
# We will only look at log lines created AFTER this point to verify device creation
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log file exists
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Ensure OpenICE is running and visible
ensure_openice_running

# Wait for OpenICE window to be sure it's ready
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected during setup"
fi

# Focus and maximize the window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial window count
# (Creating devices and opening detail views increases window count)
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Remove any existing report file to ensure a clean start
rm -f /home/ga/Desktop/device_parameter_catalog.txt 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Log start offset: $LOG_SIZE"
echo "Initial window count: $INITIAL_WINDOWS"