#!/bin/bash
echo "=== Setting up export_to_stl task ==="

# Kill any running FreeCAD
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove previous STL output for clean start
rm -f /home/ga/Documents/FreeCAD/exported_model.stl

# Ensure the real T8 housing bracket is available
# T8_housing_bracket.FCStd is from the official FreeCAD parts library:
# github.com/FreeCAD/FreeCAD-library (Mechanical Parts/Mountings/T8_housing_bracket/)
if [ ! -f /opt/freecad_samples/T8_housing_bracket.FCStd ] || \
   [ "$(stat -c%s /opt/freecad_samples/T8_housing_bracket.FCStd 2>/dev/null || echo 0)" -lt 5000 ]; then
    echo "ERROR: T8_housing_bracket.FCStd not found or too small. Setup failed."
    exit 1
fi

# Copy fresh bracket to documents
cp /opt/freecad_samples/T8_housing_bracket.FCStd /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
chown ga:ga /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd

echo "T8 bracket model size: $(stat -c%s /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd) bytes"

# Launch FreeCAD with the T8 housing bracket model
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad '/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd' > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD to fully load
sleep 14

# Show the Combo View (model tree) via View > Panels > Combo View menu
# This allows agent to click on 'Body' in the tree to select it before exporting
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 153 72 click 1 2>/dev/null || true   # View menu
sleep 0.6
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 177 603 click 1 2>/dev/null || true  # Panels
sleep 0.6
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 561 655 click 1 2>/dev/null || true  # Combo View
sleep 1

# Maximize window
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Fit view to ensure the bracket model is fully visible in the viewport
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 900 500 click 1 2>/dev/null || true
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key v 2>/dev/null || true
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key f 2>/dev/null || true
sleep 1

echo "=== export_to_stl task setup complete ==="
echo "FreeCAD is running with T8_housing_bracket.FCStd loaded."
echo "Active windows:"
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null || true
