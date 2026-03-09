#!/bin/bash
echo "=== Setting up parametric_motor_mount task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Kill any running FreeCAD
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous output files to ensure deterministic start state
rm -f /home/ga/Documents/FreeCAD/motor_mount.FCStd
rm -f /home/ga/Documents/FreeCAD/motor_mount.stl

# Verify workspace is clean
if [ -f /home/ga/Documents/FreeCAD/motor_mount.FCStd ]; then
    echo "ERROR: Could not remove previous motor_mount.FCStd"
    exit 1
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Create a task reference file for the agent (NEMA 17 specs — real standard data)
cat > /home/ga/Documents/FreeCAD/NEMA17_specifications.txt << 'SPECEOF'
NEMA 17 Stepper Motor Standard Dimensions (NEMA ICS 16)
======================================================
Motor body:          42.3mm x 42.3mm square face
Mounting holes:      4x M3 clearance holes
Hole pattern:        31mm x 31mm square (measured center-to-center)
                     Holes are symmetric about the shaft axis
Shaft collar boss:   22mm diameter (22.0mm +0/-0.1mm)
Shaft diameter:      5mm (typical)

V-slot 2020 Extrusion Attachment:
  T-slot width:      6mm
  T-nut hole:        M5 (typical), pitch = 20mm along extrusion
  Typical M5 clearance: 5.5mm hole

Design requirements:
  - Motor attachment: 4x holes at 31mm x 31mm pattern for M3 screws
  - Central bore: 22mm diameter for shaft collar alignment
  - Frame attachment: minimum 2x holes for V-slot T-nut M5 screws
  - All key dimensions driven by Spreadsheet named parameters
SPECEOF
chown ga:ga /home/ga/Documents/FreeCAD/NEMA17_specifications.txt

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

# Launch FreeCAD with empty new document
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD window to appear
sleep 14

# Create new document (Ctrl+N in case Start Center appears)
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+n 2>/dev/null || true
sleep 2

# Show the Combo View (model tree) via View > Panels > Combo View
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 153 72 click 1 2>/dev/null || true
sleep 0.6
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 177 603 click 1 2>/dev/null || true
sleep 0.6
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 561 655 click 1 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "FreeCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"
echo "NEMA17 specs written to: /home/ga/Documents/FreeCAD/NEMA17_specifications.txt"
echo "=== Setup Complete: parametric_motor_mount ==="
echo "FreeCAD is running with an empty document."
echo "Active windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
