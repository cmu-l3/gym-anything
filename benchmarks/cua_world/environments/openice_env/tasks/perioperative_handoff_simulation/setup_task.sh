#!/bin/bash
echo "=== Setting up Perioperative Device Handoff Simulation ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Record initial OpenICE log size
# We only want to analyze log entries created DURING the task
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    stat -c %s "$LOG_FILE" > /tmp/initial_log_size.txt
else
    echo "0" > /tmp/initial_log_size.txt
fi

# 3. Ensure OpenICE is running and ready
ensure_openice_running

# Wait for main window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 4. Record initial window state
DISPLAY=:1 wmctrl -l > /tmp/initial_windows.txt 2>/dev/null || true

# 5. Clean up any previous run artifacts
rm -f /home/ga/Desktop/periop_handoff_checklist.txt 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="