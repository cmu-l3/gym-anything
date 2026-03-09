#!/bin/bash
set -e
echo "=== Setting up Forced Transition Polar Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
PROJECTS_DIR="/home/ga/Documents/projects"
mkdir -p "$PROJECTS_DIR"
rm -f "$PROJECTS_DIR/forced_transition_naca0012.wpa" 2>/dev/null || true

# Ensure no previous session artifacts
pkill -f "QBlade" 2>/dev/null || true
rm -f /tmp/qblade_task.log 2>/dev/null || true

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss potential startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="