#!/bin/bash
echo "=== Setting up Closed Loop Safety Validation task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Record initial log size to only analyze new activity later
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log exists
mkdir -p /home/ga/openice/logs
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Clean up any artifacts from previous runs
rm -f /home/ga/test_step_1_nominal.png
rm -f /home/ga/test_step_2_interlock.png
rm -f /home/ga/test_step_3_recovery.png
rm -f /home/ga/Desktop/fvp_results.csv

# Record initial window state
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Take initial screenshot of the clean state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="