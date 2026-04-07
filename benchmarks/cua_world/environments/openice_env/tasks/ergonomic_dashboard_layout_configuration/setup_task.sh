#!/bin/bash
echo "=== Setting up Ergonomic Dashboard Layout Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE Supervisor (starting point)
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Remove any existing output screenshot
rm -f /home/ga/Desktop/dashboard_layout.png 2>/dev/null || true

# Take initial screenshot of the starting state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Create 3 windows (Vital Signs, Pump, Monitor) and arrange in T-Layout."