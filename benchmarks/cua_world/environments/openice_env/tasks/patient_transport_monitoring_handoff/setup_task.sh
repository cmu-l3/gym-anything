#!/bin/bash
echo "=== Setting up Patient Transport Handoff Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size to only analyze new events later
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window to be ready
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE supervisor
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up any artifacts from previous runs
rm -f /home/ga/Desktop/handoff_overlap.png
rm -f /home/ga/Desktop/transport_log.txt
rm -f /home/ga/Desktop/handoff_complete.png

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Initial Log Size: $LOG_SIZE"