#!/bin/bash
set -e
echo "=== Setting up Digital Twin Reconstruction task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up environment
echo "Cleaning workspace..."
rm -f /home/ga/Documents/projects/legacy_v1_reconstruction.wpa 2>/dev/null || true
rm -f /home/ga/Documents/projects/chord_dist.dat 2>/dev/null || true
rm -f /home/ga/Documents/projects/twist_dist.dat 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# 2. Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Launch QBlade
echo "Launching QBlade..."
launch_qblade

# 4. Wait for window and maximize
if wait_for_qblade 60; then
    echo "QBlade started successfully"
    # Wait a bit for GUI to be fully ready
    sleep 5
    
    # Attempt to maximize (QBlade often starts non-maximized)
    DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
else
    echo "WARNING: QBlade did not start within timeout"
fi

# 5. Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="