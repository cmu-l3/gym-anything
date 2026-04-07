#!/bin/bash
set -e
echo "=== Setting up device_interop_conformance_test ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial log file size (for new-lines-only analysis)
# This ensures we don't count devices created in previous sessions
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    INITIAL_LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
else
    INITIAL_LOG_SIZE=0
fi
echo "$INITIAL_LOG_SIZE" > /tmp/initial_log_size.txt
echo "Initial log size: $INITIAL_LOG_SIZE bytes"

# Record initial window count
DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l > /tmp/initial_window_count.txt
echo "Initial window count: $(cat /tmp/initial_window_count.txt)"

# Clean up any previous task artifacts to ensure clean state
rm -f /home/ga/Desktop/conformance_evidence_vitals.png 2>/dev/null || true
rm -f /home/ga/Desktop/conformance_evidence_devices.png 2>/dev/null || true
rm -f /home/ga/Desktop/dec_conformance_report.txt 2>/dev/null || true

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize the OpenICE window
sleep 3
focus_openice_window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Task artifacts cleaned. OpenICE Supervisor is running."