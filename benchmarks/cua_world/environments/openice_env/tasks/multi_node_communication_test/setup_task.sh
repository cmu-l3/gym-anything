#!/bin/bash
echo "=== Setting up Multi-Node Communication Test ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure primary OpenICE (Node A) is running
echo "Checking Node A status..."
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: Node A window not detected"
fi

# Focus and maximize Node A
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial log size of Node A to filter old events
LOG_A="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_A" ]; then
    stat -c %s "$LOG_A" > /tmp/initial_log_a_size
else
    echo "0" > /tmp/initial_log_a_size
fi

# Clean up any artifacts from previous runs
rm -f /home/ga/Desktop/node_b.log 2>/dev/null
rm -f /home/ga/Desktop/interop_report.txt 2>/dev/null
pkill -f "launch_supervisor.sh" 2>/dev/null || true
# Note: We do NOT kill the primary OpenICE instance, as that's the environment baseline

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Node A Log: $LOG_A"
echo "Instructions: Launch Node B, redirect log to /home/ga/Desktop/node_b.log"