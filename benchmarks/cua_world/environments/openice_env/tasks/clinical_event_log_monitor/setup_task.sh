#!/bin/bash
echo "=== Setting up clinical_event_log_monitor task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Clean up any previous run artifacts to ensure clean state
rm -f /home/ga/Desktop/event_monitor.sh
rm -f /home/ga/Desktop/event_summary.txt
rm -f /home/ga/Desktop/log_format_doc.txt

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window to be sure UI is ready
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial OpenICE log size
# We will only analyze log lines added AFTER this point during verification
LOG_FILE="/home/ga/openice/logs/openice.log"
# Ensure log file exists
touch "$LOG_FILE"
LOG_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
echo "$LOG_SIZE" > /tmp/initial_log_size

# Record initial window count
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Initial Log Size: $LOG_SIZE bytes"
echo "Initial Window Count: $INITIAL_WINDOWS"