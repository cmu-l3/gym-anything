#!/bin/bash
echo "=== Setting up Duplicate Device Differentiation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Clean up previous artifacts
rm -f /home/ga/Desktop/device_map.json
rm -f /home/ga/Desktop/id_evidence.png

# Record initial OpenICE log size
# We will use this to scan only NEW log entries for the UUIDs generated during the task
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

# Record initial window count
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Log offset recorded: $LOG_SIZE"