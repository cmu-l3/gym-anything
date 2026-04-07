#!/bin/bash
echo "=== Setting up Vital Sign OCR Dataset Generation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

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

# Prepare clean state: Remove dataset directory if it exists
if [ -d "/home/ga/Desktop/ocr_data" ]; then
    echo "Cleaning up existing dataset directory..."
    rm -rf "/home/ga/Desktop/ocr_data"
fi

# Ensure output directory parent exists (Desktop)
mkdir -p /home/ga/Desktop

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="