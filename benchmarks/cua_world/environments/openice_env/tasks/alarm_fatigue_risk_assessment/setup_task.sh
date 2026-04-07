#!/bin/bash
echo "=== Setting up alarm_fatigue_risk_assessment task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming (file modification checks)
date +%s > /tmp/task_start_timestamp

# Record initial OpenICE log size
# We only want to verify actions performed *during* the task
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log file exists
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE Supervisor window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected, attempting to restart..."
    pkill -f "java.*demo-apps"
    ensure_openice_running
    wait_for_window "openice|ice|supervisor|demo" 60
fi

# Focus and maximize OpenICE
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial window count and list
# This helps detect if new device/app windows are created
DISPLAY=:1 wmctrl -l > /tmp/initial_windows_list.txt
INITIAL_WINDOWS=$(wc -l < /tmp/initial_windows_list.txt)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Clean up any artifacts from previous runs to ensure clean state
rm -f /home/ga/Desktop/screenshot_vital_signs.png 2>/dev/null || true
rm -f /home/ga/Desktop/screenshot_infusion_safety.png 2>/dev/null || true
rm -f /home/ga/Desktop/alarm_fatigue_assessment.txt 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Log size: $LOG_SIZE bytes"
echo "Initial windows: $INITIAL_WINDOWS"