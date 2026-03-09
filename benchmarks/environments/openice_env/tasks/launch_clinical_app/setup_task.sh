#!/bin/bash
echo "=== Setting up launch_clinical_app task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record start timestamp
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial state
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
echo "$INITIAL_WINDOWS" > /tmp/initial_windows_list

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Launch a clinical demonstration application from the app grid"
