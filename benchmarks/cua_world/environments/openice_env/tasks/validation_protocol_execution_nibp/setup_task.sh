#!/bin/bash
echo "=== Setting up Validation Protocol: NIBP Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size (to check for NEW events only)
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

# Focus and maximize OpenICE Supervisor
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up any previous run artifacts to ensure fresh validation
rm -f /home/ga/Desktop/nibp_reading_captured.png
rm -f /home/ga/Desktop/nibp_values.txt

# Record initial window list
DISPLAY=:1 wmctrl -l > /tmp/initial_windows.txt

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Log offset: $LOG_SIZE"