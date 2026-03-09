#!/bin/bash
set -e
echo "=== Setting up Assess Prandtl Tip Loss Impact Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts
RESULTS_DIR="/home/ga/Documents/results"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# Clean up project files
rm -f /home/ga/Documents/projects/*.wpa 2>/dev/null || true
rm -f /home/ga/Documents/airfoils/*.dat 2>/dev/null || true

# 2. Record start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# 3. Ensure QBlade is running and fresh
if ! is_qblade_running > /dev/null; then
    echo "Launching QBlade..."
    launch_qblade
    sleep 5
else
    echo "QBlade already running."
fi

# 4. Wait for window and maximize
wait_for_qblade 30
if DISPLAY=:1 wmctrl -l | grep -i "QBlade"; then
    echo "Maximizing QBlade..."
    DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="