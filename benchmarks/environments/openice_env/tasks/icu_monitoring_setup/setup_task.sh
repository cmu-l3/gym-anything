#!/bin/bash
echo "=== Setting up icu_monitoring_setup task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Record initial log size (only verify NEW log entries during task)
LOG_FILE="/home/ga/openice/logs/openice.log"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial window count
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Clean up any pre-existing output file
rm -f /home/ga/Desktop/monitoring_checklist.txt 2>/dev/null || true

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Log size: $LOG_SIZE bytes | Initial windows: $INITIAL_WINDOWS"
