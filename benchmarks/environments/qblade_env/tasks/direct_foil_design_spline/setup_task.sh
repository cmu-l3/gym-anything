#!/bin/bash
set -e
echo "=== Setting up Direct Foil Design task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state
# Remove the target file if it exists from a previous run
rm -f /home/ga/Documents/projects/custom_spline_foil.wpa 2>/dev/null || true
# Ensure project directory exists
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents/projects

# 3. Launch Application
# Kill any existing QBlade instances
pkill -f "[Qq][Bb]lade" 2>/dev/null || true
sleep 2

# Launch QBlade (no project loaded, fresh start)
echo "Launching QBlade..."
launch_qblade
sleep 8

# 4. Wait for window and optimize view
wait_for_qblade 45

# Maximize window (CRITICAL for VLM)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/splash screens if present
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 5. Capture initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="