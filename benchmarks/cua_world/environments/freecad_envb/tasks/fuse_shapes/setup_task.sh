#!/bin/bash
echo "=== Setting up fuse_shapes task ==="

# Kill any running FreeCAD
pkill -f freecad 2>/dev/null || true
sleep 2

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove previous output for clean start
rm -f /home/ga/Documents/FreeCAD/fused_model.FCStd

# Ensure the real contact blocks model is available
# contact_blocks.FCStd is derived from FreeCAD's own FEM test suite:
# freecad/Mod/Fem/femtest/data/calculix/constraint_contact_solid_solid.FCStd
# The two solid blocks (TopBox, BottomBox) represent a real contact mechanics scenario.
if [ ! -f /opt/freecad_samples/contact_blocks.FCStd ] || \
   [ "$(stat -c%s /opt/freecad_samples/contact_blocks.FCStd 2>/dev/null || echo 0)" -lt 5000 ]; then
    echo "ERROR: contact_blocks.FCStd not found or too small. Setup failed."
    exit 1
fi

# Copy fresh contact_blocks to documents
cp /opt/freecad_samples/contact_blocks.FCStd /home/ga/Documents/FreeCAD/contact_blocks.FCStd
chown ga:ga /home/ga/Documents/FreeCAD/contact_blocks.FCStd

echo "Contact blocks model size: $(stat -c%s /home/ga/Documents/FreeCAD/contact_blocks.FCStd) bytes"

# Launch FreeCAD with the contact blocks model
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad '/home/ga/Documents/FreeCAD/contact_blocks.FCStd' > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD to fully load
sleep 14

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
sleep 2

# Fit view to ensure both blocks are visible in the viewport
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 900 500 click 1 2>/dev/null || true
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key v 2>/dev/null || true
sleep 0.3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key f 2>/dev/null || true
sleep 1

echo "=== fuse_shapes task setup complete ==="
echo "FreeCAD is running with contact_blocks.FCStd loaded."
echo "Active windows:"
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null || true
