#!/bin/bash
echo "=== Setting up eia_rack_panel_design task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Kill any running FreeCAD
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous output files
rm -f /home/ga/Documents/FreeCAD/rack_panel.FCStd
rm -f /home/ga/Documents/FreeCAD/rack_panel.step
rm -f /home/ga/Documents/FreeCAD/rack_panel.stp

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Write EIA-310 specification reference file (real standard data)
cat > /home/ga/Documents/FreeCAD/EIA310_rack_panel_spec.txt << 'SPECEOF'
EIA-310-D Rack Panel Specification — 1U 19-inch
================================================
Standard:     ANSI/EIA-310-D (Electronic Industries Alliance)
Panel size:   1U (1 rack unit) = 44.45mm tall x 482.6mm wide
Thickness:    2.0mm (aluminum sheet, typical)

Rack-ear mounting holes (per EIA-310 standard):
  - 2 holes per ear (left and right ears), 4 holes total
  - Vertical centers: 31.75mm (1.25 inch) between holes per ear
  - Top hole from panel edge: ~6.35mm
  - From panel side edge to hole center: ~7.94mm
  - Hole size: M6 clearance (6.5mm diameter)

Connector cutouts required:
  1. BNC connector #1 (left side):  15.0mm diameter circular cutout
  2. BNC connector #2 (left side):  15.0mm diameter circular cutout
  3. DE-9 (D-sub 9-pin) connector:  31.6mm wide x 12.5mm tall rectangular cutout

Design must be parametric:
  - Panel height, panel width, panel thickness as Spreadsheet parameters
  - BNC cutout diameter as a Spreadsheet parameter

Output files:
  - Save as: /home/ga/Documents/FreeCAD/rack_panel.FCStd
  - Export STEP to: /home/ga/Documents/FreeCAD/rack_panel.step
SPECEOF
chown ga:ga /home/ga/Documents/FreeCAD/EIA310_rack_panel_spec.txt

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
echo "EIA-310 spec written to: /home/ga/Documents/FreeCAD/EIA310_rack_panel_spec.txt"
echo "=== Setup Complete: eia_rack_panel_design ==="
echo "FreeCAD is running with an empty document."
echo "Active windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
