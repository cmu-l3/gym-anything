#!/bin/bash
echo "=== Setting up sedation_monitoring_protocol task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming (file mtime checks)
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size 
# (We only want to score actions performed DURING the task, not previous runs)
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log file exists
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Ensure clean state for the protocol file
rm -f /home/ga/Desktop/sedation_monitoring_protocol.txt 2>/dev/null || true

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE Supervisor window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE to ensure agent sees it clearly
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial window count (to detect creation of device/app windows)
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Log size: $LOG_SIZE bytes | Initial windows: $INITIAL_WINDOWS"