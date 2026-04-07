#!/bin/bash
echo "=== Setting up Hemodynamic Instability Monitoring Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size to only analyze new entries later
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log file exists
mkdir -p /home/ga/openice/logs
touch "$LOG_FILE"
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

# Record initial window count
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Clean up any pre-existing output files
rm -f /home/ga/Desktop/shock_protocol_status.txt 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Log size: $LOG_SIZE bytes"
echo "Initial windows: $INITIAL_WINDOWS"