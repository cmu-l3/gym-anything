#!/bin/bash
set -e
echo "=== Setting up create_helical_lead_screw task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ensure directory exists and is clean
mkdir -p /home/ga/Documents/FreeCAD
rm -f /home/ga/Documents/FreeCAD/lead_screw.FCStd
rm -f /home/ga/Documents/FreeCAD/lead_screw.step
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any running FreeCAD instance
kill_freecad

# Launch FreeCAD with a new empty document
# We suppress the start center in user.cfg (done in env setup), so this opens a blank window
launch_freecad

# Wait for FreeCAD to load
wait_for_freecad 30

# Maximize window
maximize_freecad

# Ensure we have a new document active (Ctrl+N)
# Even if one opens by default, a second blank one doesn't hurt and ensures a clean state
su - ga -c "DISPLAY=:1 xdotool key ctrl+n"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="