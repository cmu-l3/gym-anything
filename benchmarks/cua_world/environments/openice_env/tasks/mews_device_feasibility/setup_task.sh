#!/bin/bash
echo "=== Setting up MEWS Device Feasibility Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt

# 2. Record initial state of OpenICE logs (to only scan new lines later)
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log file exists
touch "$LOG_FILE"
# Record byte offset
stat -c %s "$LOG_FILE" > /tmp/initial_log_size.txt

# 3. Record initial windows (to detect new device windows)
DISPLAY=:1 wmctrl -l > /tmp/initial_windows.txt

# 4. Clean up previous artifacts if they exist
rm -f /home/ga/Desktop/mews_monitoring_screenshot.png
rm -f /home/ga/Desktop/mews_feasibility_assessment.txt

# 5. Ensure OpenICE is running and ready
ensure_openice_running

# Wait for UI to be ready
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Log offset recorded: $(cat /tmp/initial_log_size.txt)"