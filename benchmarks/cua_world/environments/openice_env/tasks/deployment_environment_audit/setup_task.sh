#!/bin/bash
echo "=== Setting up deployment_environment_audit task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record start timestamp for verification
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size (to check for new devices later)
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

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up any previous audit file
rm -f /home/ga/Desktop/deployment_audit.txt 2>/dev/null || true

# Record initial window count
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Log size recorded: $LOG_SIZE bytes"