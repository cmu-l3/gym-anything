#!/bin/bash
set -e
echo "=== Setting up create_polar_pattern task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -f freecad 2>/dev/null || true
sleep 2

# Create workspace directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove output file if it exists from previous run
rm -f /home/ga/Documents/FreeCAD/nema23_motor_flange.FCStd

# Start FreeCAD with a fresh empty document
# We suppress the Start Center in user.cfg (done in env setup), so this opens empty
su - ga -c "DISPLAY=:1 freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for FreeCAD..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD" > /dev/null; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Ensure Part Design workbench is accessible or active
# (Agent should know how to switch, but we make sure UI is ready)
sleep 5

# Dismiss any startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="