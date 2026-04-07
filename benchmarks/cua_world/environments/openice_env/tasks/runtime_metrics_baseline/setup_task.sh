#!/bin/bash
set -e
echo "=== Setting up runtime_metrics_baseline task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# Record initial OpenICE log size
# We will only scan log lines added AFTER this point to detect device creation
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    stat -c %s "$LOG_FILE" > /tmp/initial_log_size.txt
else
    echo "0" > /tmp/initial_log_size.txt
fi

# Ensure OpenICE Supervisor is running
ensure_openice_running

# Wait for OpenICE window
echo "Waiting for OpenICE window..."
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected, attempting to restart..."
    pkill -f "java.*demo-apps" || true
    ensure_openice_running
    wait_for_window "openice|ice|supervisor|demo" 60
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial window count (to detect new device windows)
DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l > /tmp/initial_window_count.txt

# Ensure the report file does NOT exist (clean state)
rm -f /home/ga/Desktop/performance_baseline.txt 2>/dev/null || true

# Open a terminal for the user (since they need to run commands)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Launching terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal &"
    sleep 3
fi

# Minimize the terminal so OpenICE is visible initially, but terminal is ready in taskbar
# (Optional, but keeps the initial view clean as per description)
DISPLAY=:1 wmctrl -r "Terminal" -b add,hidden 2>/dev/null || true
# Re-focus OpenICE
focus_openice_window

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="