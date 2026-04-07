#!/bin/bash
echo "=== Setting up safety_interlock_fail_safe_validation task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Record initial log size to only analyze new log entries
LOG_FILE="/home/ga/openice/logs/openice.log"
touch "$LOG_FILE" # Ensure it exists
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up previous artifacts
rm -f /home/ga/Desktop/test_01_baseline.png
rm -f /home/ga/Desktop/test_02_failsafe.png
rm -f /home/ga/Desktop/failsafe_report.txt

# Take initial state screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Log offset: $LOG_SIZE"