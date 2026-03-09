#!/bin/bash
set -e
echo "=== Setting up create_parametric_standoff task ==="

# 1. Kill any running FreeCAD instances
pkill -f freecad 2>/dev/null || true
sleep 2

# 2. Setup clean workspace
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove previous output to ensure clean state
rm -f /home/ga/Documents/FreeCAD/parametric_standoff.FCStd

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch FreeCAD (headless first to check config, but here we just launch GUI)
# We use su - ga to run as the user
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for FreeCAD window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "FreeCAD" > /dev/null; then
        echo "FreeCAD window detected."
        break
    fi
    sleep 1
done
sleep 5 # Extra buffer for UI initialization

# 6. Ensure the Combo View (Model Tree) is visible
# This is critical for the agent to see the Spreadsheet and Body
# We click View (menu) -> Panels -> Combo View
# Coordinates are approximate based on standard Gnome layout; fallback to shortcut if available
# FreeCAD doesn't have a universal shortcut for Combo View, so we rely on default layout.
# If panels are messed up, we try to reset. For now, we assume default config from env setup.

# 7. Maximize window
DISPLAY=:1 wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# 8. Create a new document automatically to save agent one step
# (Optional, but helps standardize starting state)
DISPLAY=:1 xdotool key ctrl+n 2>/dev/null || true
sleep 1

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="