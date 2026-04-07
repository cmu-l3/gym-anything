#!/bin/bash
echo "=== Setting up Longitudinal Physiological Sampling task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
# We use this to ensure the agent actually spent time collecting data
date +%s > /tmp/task_start_timestamp

# Ensure clean state - remove files if they exist from previous runs
rm -f /home/ga/Desktop/monitor_sample.csv
rm -f /home/ga/Desktop/sample_analysis.txt

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

# Record initial log size to check for new device creation events later
LOG_FILE="/home/ga/openice/logs/openice.log"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Cleaned previous data files."
echo "OpenICE running and focused."