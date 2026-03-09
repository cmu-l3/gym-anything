#!/bin/bash
set -e
echo "=== Setting up task: Set TE Gap on NACA 4415 ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Remove any pre-existing output file to ensure clean state
rm -f /home/ga/Documents/airfoils/naca4415_bluntTE.dat 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure target directory exists
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents/airfoils

# Kill any existing QBlade instances for clean state
pkill -f "[Qq][Bb]lade" 2>/dev/null || true
sleep 2

# Launch QBlade
echo "Launching QBlade..."
launch_qblade
sleep 8

# Wait for QBlade window
if wait_for_qblade 45; then
    echo "QBlade window detected successfully"
else
    echo "WARNING: QBlade window not detected, attempting relaunch..."
    launch_qblade
    sleep 10
    wait_for_qblade 30
fi

# Maximize and focus QBlade window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Try to find and focus the QBlade window specifically
QBLADE_WIN=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "qblade" | head -1 | awk '{print $1}')
if [ -n "$QBLADE_WIN" ]; then
    DISPLAY=:1 wmctrl -i -a "$QBLADE_WIN" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$QBLADE_WIN" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "QBlade window focused and maximized: $QBLADE_WIN"
fi

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png
echo "Initial state screenshot saved"

echo "=== Task setup complete ==="
echo "Target output: /home/ga/Documents/airfoils/naca4415_bluntTE.dat"