#!/bin/bash
echo "=== Setting up add_dimensions task ==="

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Ensure the real floor plan is available
if [ ! -s /home/ga/Documents/LibreCAD/floorplan.dxf ]; then
    cp /opt/librecad_samples/floorplan.dxf /home/ga/Documents/LibreCAD/floorplan.dxf 2>/dev/null || true
fi

# Remove any previous output file
rm -f /home/ga/Documents/LibreCAD/floorplan_dims.dxf

chown -R ga:ga /home/ga/Documents/LibreCAD

# Open LibreCAD with the real floor plan drawing
su - ga -c "DISPLAY=:1 librecad /home/ga/Documents/LibreCAD/floorplan.dxf > /tmp/librecad_task.log 2>&1 &"
sleep 8

# Maximize the window
DISPLAY=:1 wmctrl -r "floorplan" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== add_dimensions task setup complete ==="
