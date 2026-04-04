#!/bin/bash
echo "=== Setting up structural_gusset_plate task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Kill any running FreeCAD
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous output files
rm -f /home/ga/Documents/FreeCAD/gusset_plate.FCStd
rm -f /home/ga/Documents/FreeCAD/gusset_plate.step
rm -f /home/ga/Documents/FreeCAD/gusset_plate.stp

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Write AISC gusset plate specification reference file (real standard data)
cat > /home/ga/Documents/FreeCAD/AISC_gusset_plate_spec.txt << 'SPECEOF'
Structural Steel Gusset Plate Connection — Design Specification
===============================================================
Reference: AISC Steel Construction Manual, 15th Edition
Connection: HSS diagonal brace to W8x31 wide-flange column

Gusset plate dimensions:
  Width:      250mm (measured along column face)
  Height:     200mm (measured perpendicular to column)
  Thickness:  12mm (ASTM A36 structural plate)

Brace bolt group (upper-left quadrant of plate):
  Purpose:    Connects to diagonal HSS brace end plate
  Bolt size:  M20 (clearance hole = 22mm diameter)
  Layout:     2 columns x 2 rows = 4 bolts
  Gauge:      70mm (column-to-column spacing)
  Pitch:      75mm (row-to-row spacing)
  Edge dist:  40mm minimum from plate edge (AISC requirement)

Column bolt group (left edge, for column flange attachment):
  Purpose:    Welds/bolts to W8x31 column flange
  Bolt size:  M20 (clearance hole = 22mm diameter)
  Layout:     2 columns x 2 rows = 4 bolts
  Gauge:      70mm
  Pitch:      75mm
  Position:   Along left edge of plate

Weld preparation:
  Location:   Top edge (brace attachment edge)
  Type:       45-degree chamfer (weld bevel)
  Depth:      6mm (standard AWS D1.1 weld prep)

Bill of Materials (Spreadsheet):
  Named parameters: plate_width, plate_height, plate_thickness,
                    bolt_diameter, gauge, pitch

Output files:
  - Save as:    /home/ga/Documents/FreeCAD/gusset_plate.FCStd
  - Export STEP: /home/ga/Documents/FreeCAD/gusset_plate.step
SPECEOF
chown ga:ga /home/ga/Documents/FreeCAD/AISC_gusset_plate_spec.txt

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
echo "AISC gusset plate spec written to: /home/ga/Documents/FreeCAD/AISC_gusset_plate_spec.txt"
echo "=== Setup Complete: structural_gusset_plate ==="
echo "FreeCAD is running with an empty document."
echo "Active windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
