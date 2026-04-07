#!/bin/bash
echo "=== Setting up Ward Monitoring Configuration task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming (only accept IDs generated after this)
date +%s > /tmp/task_start_timestamp

# Ensure OpenICE logs directory exists
mkdir -p /home/ga/openice/logs

# Record initial log size to only analyze NEW logs later
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    stat -c %s "$LOG_FILE" > /tmp/initial_log_size
else
    echo "0" > /tmp/initial_log_size
fi

# Clean up any previous run artifacts
rm -f /home/ga/Desktop/ward_config.csv 2>/dev/null || true

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window to appear
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial window count
DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l > /tmp/initial_window_count

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="