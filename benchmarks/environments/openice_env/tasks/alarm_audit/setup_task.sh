#!/bin/bash
echo "=== Setting up alarm_audit task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

LOG_FILE="/home/ga/openice/logs/openice.log"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

ensure_openice_running

if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

rm -f /home/ga/Desktop/alarm_audit.txt 2>/dev/null || true

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Log size: $LOG_SIZE | Initial windows: $INITIAL_WINDOWS"
