#!/bin/bash
echo "=== Setting up ICU Device Inventory Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

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

# CRITICAL: Record the byte offset of the log file.
# We only want to verify devices created *during* this task, not old ones.
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    stat -c %s "$LOG_FILE" > /tmp/initial_log_offset
else
    echo "0" > /tmp/initial_log_offset
fi

# Clean up any previous inventory file
rm -f /home/ga/Desktop/icu_inventory.csv 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Initial log offset recorded: $(cat /tmp/initial_log_offset)"