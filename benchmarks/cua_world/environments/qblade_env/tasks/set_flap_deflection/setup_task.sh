#!/bin/bash
set -euo pipefail

echo "=== Setting up Set Flap Deflection task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/Documents/airfoils/naca4415_original.dat 2>/dev/null || true
rm -f /home/ga/Documents/airfoils/naca4415_flap10.dat 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure airfoils directory exists
mkdir -p /home/ga/Documents/airfoils
chown ga:ga /home/ga/Documents/airfoils

# Ensure QBlade is not already running (clean state)
pkill -f "[Qq][Bb]lade" 2>/dev/null || true
sleep 2

# Launch QBlade using the shared utility
echo "Launching QBlade..."
launch_qblade
sleep 5

# Wait for QBlade window to appear
wait_for_qblade 60

# Maximize the window (critical for agent visibility)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true
sleep 1

# Dismiss any potential startup dialogs/popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="