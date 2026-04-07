#!/bin/bash
set -e
echo "=== Setting up medical_device_network_security_review task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial OpenICE log size
# We will only analyze log lines added AFTER this point to detect device creation
OPENICE_LOG="/home/ga/openice/logs/openice.log"
if [ -f "$OPENICE_LOG" ]; then
    stat -c%s "$OPENICE_LOG" > /tmp/initial_log_size.txt
else
    echo "0" > /tmp/initial_log_size.txt
fi

# Record initial window state
DISPLAY=:1 wmctrl -l 2>/dev/null > /tmp/initial_windows.txt || true
wc -l < /tmp/initial_windows.txt > /tmp/initial_window_count.txt

# Remove any previous report file
rm -f /home/ga/Desktop/openice_security_assessment.txt

# Install necessary network analysis tools if missing
# (The environment has base tools, but ensure net-tools/lsof are present for the analyst)
apt-get update && apt-get install -y net-tools lsof iproute2 > /dev/null 2>&1 || true

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE Supervisor window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected during setup"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="
echo "Report expected at: /home/ga/Desktop/openice_security_assessment.txt"