#!/bin/bash
echo "=== Setting up Regulatory Audit Trail Preservation task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Ensure OpenICE is running (task requires interacting with it)
ensure_openice_running

# Wait for OpenICE window to appear
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial log size to track new activity if needed
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    stat -c %s "$LOG_FILE" > /tmp/initial_log_size
else
    echo "0" > /tmp/initial_log_size
fi

# Clean up any artifacts from previous runs to ensure a clean state
AUDIT_DIR="/home/ga/Desktop/QA_Audit_2026"
if [ -d "$AUDIT_DIR" ]; then
    echo "Cleaning up existing audit directory..."
    rm -rf "$AUDIT_DIR"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task ready."