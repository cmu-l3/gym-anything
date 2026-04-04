#!/bin/bash
echo "=== Setting up create_simulated_device task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record start timestamp for verification
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure OpenICE is running
ensure_openice_running

# Wait for OpenICE window
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected"
fi

# Focus and maximize OpenICE window
focus_openice_window
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record initial state - count existing device windows/indicators
# OpenICE shows device icons in the right panel
INITIAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
echo "$INITIAL_WINDOWS" > /tmp/initial_window_count

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Initial window count: $INITIAL_WINDOWS"
echo "Task: Create a Simulated Multiparameter Monitor device adapter"
