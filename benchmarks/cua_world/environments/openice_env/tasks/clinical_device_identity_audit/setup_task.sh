#!/bin/bash
echo "=== Setting up Clinical Device Identity Audit ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Clean up previous artifacts
rm -f /home/ga/Desktop/device_identity_map.csv 2>/dev/null || true

# Record initial log size to only analyze NEW logs later
# This helps us isolate UUIDs generated during THIS session
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    stat -c %s "$LOG_FILE" > /tmp/initial_log_size
else
    echo "0" > /tmp/initial_log_size
fi

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
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Cleaned /home/ga/Desktop/device_identity_map.csv"
echo "Initial window count: $INITIAL_WINDOWS"