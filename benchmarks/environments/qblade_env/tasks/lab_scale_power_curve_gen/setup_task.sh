#!/bin/bash
set -e
echo "=== Setting up Lab Scale Power Curve Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# Clean up any previous results to ensure fresh generation
rm -f /home/ga/Documents/projects/lab_power_curve.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure QBlade is running
if ! is_qblade_running > /dev/null; then
    echo "Starting QBlade..."
    launch_qblade
    
    # Wait for window
    if wait_for_qblade 60; then
        echo "QBlade started successfully"
    else
        echo "ERROR: QBlade failed to start"
        exit 1
    fi
else
    echo "QBlade is already running"
fi

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="