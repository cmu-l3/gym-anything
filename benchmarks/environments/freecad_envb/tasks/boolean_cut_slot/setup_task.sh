#!/bin/bash
set -e
echo "=== Setting up boolean_cut_slot task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean any previous output to ensure a fresh start
rm -f /home/ga/Documents/FreeCAD/slotted_cylinder.FCStd
rm -f /tmp/task_result.json

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Kill any existing FreeCAD instance
kill_freecad
sleep 2

# Launch FreeCAD with no file (empty/new document)
# We use the 'launch_freecad' helper from task_utils.sh
launch_freecad
sleep 5

# Wait for FreeCAD window to appear
wait_for_freecad 40

# Maximize the window (CRITICAL for agent visibility)
maximize_freecad
sleep 2

# Ensure Part workbench is loaded or at least FreeCAD is ready
# (The user.cfg in setup_freecad.sh sets Part workbench as default, so it should be fine)

# Take initial screenshot of the empty/starter state
take_screenshot /tmp/task_initial.png

echo "=== boolean_cut_slot setup complete ==="