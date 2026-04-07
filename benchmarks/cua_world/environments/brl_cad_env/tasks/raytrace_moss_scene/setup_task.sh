#!/bin/bash
echo "=== Setting up raytrace_moss_scene task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Kill any running MGED instance
kill_mged

# Verify moss.g is available (official BRL-CAD benchmark scene)
# moss.g contains: ellipsoid, torus, box, wedge on a ground plane
if [ ! -f /opt/brlcad_samples/moss.g ] || \
   [ "$(stat -c%s /opt/brlcad_samples/moss.g 2>/dev/null || echo 0)" -lt 1000 ]; then
    echo "ERROR: moss.g not found or too small at /opt/brlcad_samples/moss.g"
    exit 1
fi

# Copy fresh moss.g to user workspace
cp /opt/brlcad_samples/moss.g /home/ga/Documents/BRLCAD/moss.g
chown ga:ga /home/ga/Documents/BRLCAD/moss.g
echo "moss.g size: $(stat -c%s /home/ga/Documents/BRLCAD/moss.g) bytes"

# Write .mgedrc to auto-draw all geometry on startup
write_mgedrc "e all.g" "ae 35 25" "autoview"

# Launch MGED with moss.g
launch_mged /home/ga/Documents/BRLCAD/moss.g

# Wait for MGED windows to appear
wait_for_mged 45

# Wait for .mgedrc after-script to execute (2s delay + draw time)
sleep 5

# Position windows: Command Window left, Graphics Window right
position_mged_windows
sleep 1

echo "=== raytrace_moss_scene task setup complete ==="
echo "MGED is running with moss.g loaded and all.g drawn."
echo "Active windows:"
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null || true
