#!/bin/bash
# setup_task.sh - Pre-task hook for gas_alarm_setpoint_calculation

echo "=== Setting up gas_alarm_setpoint_calculation task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# clean up previous run artifacts
rm -f /home/ga/Documents/alarm_setpoints.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch Firefox to CAMEO Chemicals homepage
echo "Launching Firefox..."
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"
else
    # Fallback if utils not present
    su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"
    sleep 10
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="