#!/bin/bash
echo "=== Setting up create_box task ==="

# Kill any running FreeCAD
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous output to ensure deterministic start state
rm -f /home/ga/Documents/FreeCAD/box_model.FCStd

# Launch FreeCAD with no file (suppressed Start Center via user.cfg)
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD window to appear
sleep 12

# Ensure we have a new Part document (Ctrl+N creates new document, then set Part workbench)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+n 2>/dev/null || true
sleep 2

# Show the Combo View (model tree) via View > Panels > Combo View menu
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 153 72 click 1 2>/dev/null || true   # View menu
sleep 0.6
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 177 603 click 1 2>/dev/null || true  # Panels
sleep 0.6
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 561 655 click 1 2>/dev/null || true  # Combo View
sleep 1

# Maximize window
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== create_box task setup complete ==="
echo "FreeCAD is running. Agent should see FreeCAD with a new empty document."
echo "Active windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
