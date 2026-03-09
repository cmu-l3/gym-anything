#!/bin/bash
echo "=== Setting up draw_rectangle task ==="

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 2

# Ensure output directory exists
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Remove any previous output file to ensure clean state
rm -f /home/ga/Documents/LibreCAD/rectangle_task.dxf

# Open LibreCAD with a new empty drawing (no file argument = new drawing)
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"
sleep 6

# Maximize the window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== draw_rectangle task setup complete ==="
