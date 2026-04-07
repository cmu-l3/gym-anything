#!/bin/bash
echo "=== Setting up spo2_alarm_limit_validation task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size to only analyze new entries later
LOG_FILE="/home/ga/openice/logs/openice.log"
mkdir -p "$(dirname "$LOG_FILE")"
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

# Clean up previous artifacts
rm -f /home/ga/Desktop/alarm_trigger_evidence.png 2>/dev/null || true
rm -f /home/ga/Desktop/alarm_threshold_report.json 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Log size recorded: $LOG_SIZE"