#!/bin/bash
echo "=== Setting up clinical_app_evaluation_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window to be visible
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial log size
# We will only analyze log lines written AFTER this point to detect agent actions
LOG_FILE="/home/ga/openice/logs/openice.log"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Record initial window count
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Remove any pre-existing report file to ensure a clean state
rm -f /home/ga/Desktop/clinical_app_evaluation.txt 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Log offset recorded: $LOG_SIZE bytes"
echo "Initial window count: $INITIAL_WINDOWS"