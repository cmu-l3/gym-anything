#!/bin/bash
echo "=== Setting up robot_arm_link_drawings task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Kill any running FreeCAD
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous output files
rm -f /home/ga/Documents/FreeCAD/bracket_drawing.FCStd
rm -f /home/ga/Documents/FreeCAD/bracket_drawing.pdf

# Ensure the T8 housing bracket model is available
if [ ! -f /opt/freecad_samples/T8_housing_bracket.FCStd ] || \
   [ "$(stat -c%s /opt/freecad_samples/T8_housing_bracket.FCStd 2>/dev/null || echo 0)" -lt 5000 ]; then
    echo "ERROR: T8_housing_bracket.FCStd not found or too small in /opt/freecad_samples/. Setup failed."
    exit 1
fi

# Copy fresh source model to workspace
cp /opt/freecad_samples/T8_housing_bracket.FCStd /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
chown ga:ga /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd
echo "T8_housing_bracket.FCStd: $(stat -c%s /home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd) bytes"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Write a drawing requirements reference file
cat > /home/ga/Documents/FreeCAD/drawing_requirements.txt << 'REQEOF'
Engineering Drawing Requirements — T8 Lead Screw Housing Bracket
================================================================
Source model: T8_housing_bracket.FCStd (T8 lead screw linear motion bracket)

Required drawing content:
  1. Front orthographic projection view
  2. Right-side orthographic projection view
  3. Top orthographic projection view
  4. At least one isometric or perspective view
  5. At least 6 dimension annotations covering:
     - Overall length, width, height
     - Mounting hole center distances
     - Key feature dimensions

Output files:
  - Save drawing as: /home/ga/Documents/FreeCAD/bracket_drawing.FCStd
  - Export PDF to:   /home/ga/Documents/FreeCAD/bracket_drawing.pdf
REQEOF
chown ga:ga /home/ga/Documents/FreeCAD/drawing_requirements.txt

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

# Launch FreeCAD with the T8 bracket model
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad '/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd' > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD to fully load the model
sleep 14

# Show the Combo View (model tree)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 153 72 click 1 2>/dev/null || true
sleep 0.6
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 177 603 click 1 2>/dev/null || true
sleep 0.6
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 561 655 click 1 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Fit view to show the bracket
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 900 500 click 1 2>/dev/null || true
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key v 2>/dev/null || true
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key f 2>/dev/null || true
sleep 1

echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"
echo "=== Setup Complete: robot_arm_link_drawings ==="
echo "FreeCAD is running with T8_housing_bracket.FCStd loaded."
echo "Agent must create TechDraw drawing page, add views, add dimensions, export PDF."
echo "Active windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
