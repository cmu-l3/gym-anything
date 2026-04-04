#!/bin/bash
echo "=== Setting up export_to_pdf task ==="

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Ensure the floor plan DXF is available
if [ ! -s /home/ga/Documents/LibreCAD/floorplan.dxf ]; then
    cp /opt/librecad_samples/floorplan.dxf /home/ga/Documents/LibreCAD/floorplan.dxf 2>/dev/null || true
fi

# Remove any previous PDF output
rm -f /home/ga/Documents/LibreCAD/floorplan_export.pdf

chown -R ga:ga /home/ga/Documents/LibreCAD

# Open LibreCAD with the floor plan drawing
su - ga -c "DISPLAY=:1 librecad /home/ga/Documents/LibreCAD/floorplan.dxf > /tmp/librecad_task.log 2>&1 &"
sleep 6

# Maximize the window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== export_to_pdf task setup complete ==="
