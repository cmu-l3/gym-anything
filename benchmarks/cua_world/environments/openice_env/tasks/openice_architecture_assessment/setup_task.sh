#!/bin/bash
set -e
echo "=== Setting up OpenICE Architecture Assessment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial log file size (to analyze only NEW lines later)
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    INITIAL_LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
else
    INITIAL_LOG_SIZE=0
fi
echo "$INITIAL_LOG_SIZE" > /tmp/initial_log_size
echo "Initial log size: $INITIAL_LOG_SIZE bytes"

# Record initial window state
DISPLAY=:1 wmctrl -l 2>/dev/null > /tmp/initial_windows.txt || true
INITIAL_WINDOW_COUNT=$(wc -l < /tmp/initial_windows.txt)
echo "$INITIAL_WINDOW_COUNT" > /tmp/initial_window_count.txt

# Remove any pre-existing report file
rm -f /home/ga/Desktop/openice_architecture_assessment.txt 2>/dev/null || true

# Ensure OpenICE is running
ensure_openice_running

# Focus and maximize OpenICE window
sleep 3
focus_openice_window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs if present
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Source code available at: /opt/openice/mdpnp/"
echo "Target report path: /home/ga/Desktop/openice_architecture_assessment.txt"