#!/bin/bash
echo "=== Setting up Adverse Event RCA Reconstruction task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 2. Record initial OpenICE log size
# We will only analyze log lines written AFTER this point to detect agent actions
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log file exists
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# 3. Ensure OpenICE is running
ensure_openice_running

# 4. Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# 5. Focus and maximize OpenICE
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Record initial window count
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# 7. Clean up any previous report file
rm -f /home/ga/Desktop/rca_report.txt 2>/dev/null || true

# 8. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Log size recorded: $LOG_SIZE bytes"
echo "Initial window count: $INITIAL_WINDOWS"