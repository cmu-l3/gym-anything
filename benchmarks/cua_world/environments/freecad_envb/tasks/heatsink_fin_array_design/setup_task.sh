#!/bin/bash
echo "=== Setting up heatsink_fin_array_design task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Kill any running FreeCAD
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous output files
rm -f /home/ga/Documents/FreeCAD/heatsink.FCStd
rm -f /home/ga/Documents/FreeCAD/heatsink.stl
rm -f /home/ga/Documents/FreeCAD/heatsink.step
rm -f /home/ga/Documents/FreeCAD/heatsink.stp

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Write TO-220 specification reference file (real JEDEC standard data)
cat > /home/ga/Documents/FreeCAD/TO220_heatsink_spec.txt << 'SPECEOF'
Heatsink Design Specification — TO-220 Power Package
=====================================================
Package standard: JEDEC TO-220 (JESD77-B)

TO-220 package mounting surface dimensions:
  Mounting surface width:   15.9mm
  Mounting surface height:  10.15mm
  Mounting hole diameter:   3.5mm
  Mounting hole offset:     5.08mm from package body edge (center)

Power requirement: 100W continuous dissipation
Environment: Still air (natural convection)

Heatsink design guidelines (standard engineering practice):
  Base plate:    Flat aluminum plate >= 20mm x 16mm x 4mm thick (minimum)
  Fins:          At least 8 fins for adequate surface area at 100W in still air
  Fin height:    Recommended 20-30mm
  Fin thickness: Recommended 1.5-2.0mm
  Fin pitch:     Recommended 4-6mm (center-to-center)
  Material:      Aluminum (thermal conductivity ~167 W/(m*K))

Mounting holes (for chassis/PCB attachment):
  Minimum 2x holes, M3 clearance (3.4mm diameter)
  Position outside the fin array footprint

Parametric design (Spreadsheet named parameters required):
  - fin_count     (number of fins, minimum 8)
  - fin_height    (height of each fin in mm)
  - fin_thickness (fin wall thickness in mm)
  - base_thickness (base plate thickness in mm)

Output files:
  - Save as:     /home/ga/Documents/FreeCAD/heatsink.FCStd
  - Export STL:  /home/ga/Documents/FreeCAD/heatsink.stl
  - Export STEP: /home/ga/Documents/FreeCAD/heatsink.step
SPECEOF
chown ga:ga /home/ga/Documents/FreeCAD/TO220_heatsink_spec.txt

# Take initial screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_start_screenshot.png 2>/dev/null || true

# Launch FreeCAD with empty document
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD window
sleep 14

# Create new document
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+n 2>/dev/null || true
sleep 2

# Show Combo View
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
echo "TO-220 spec written to: /home/ga/Documents/FreeCAD/TO220_heatsink_spec.txt"
echo "=== Setup Complete: heatsink_fin_array_design ==="
echo "FreeCAD is running with an empty document."
echo "Active windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
