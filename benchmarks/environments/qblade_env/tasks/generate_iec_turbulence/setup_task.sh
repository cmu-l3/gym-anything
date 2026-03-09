#!/bin/bash
set -e
echo "=== Setting up generate_iec_turbulence task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/windfields
chown ga:ga /home/ga/Documents/windfields

# Remove any previous output file to ensure fresh generation
rm -f "/home/ga/Documents/windfields/kaimal_18ms_turb.bin"

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window to appear
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Dismiss any startup dialogs (Esc key)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="