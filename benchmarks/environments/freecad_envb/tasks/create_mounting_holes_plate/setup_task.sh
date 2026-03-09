#!/bin/bash
set -e
echo "=== Setting up create_mounting_holes_plate task ==="

# 1. Basic environment setup
source /workspace/scripts/task_utils.sh

# 2. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous artifacts
OUTPUT_PATH="/home/ga/Documents/FreeCAD/mounting_plate.FCStd"
rm -f "$OUTPUT_PATH"
# Also clean up any autosaves/backups
rm -f /home/ga/Documents/FreeCAD/*.FCStd*

# 4. Ensure directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# 5. Launch FreeCAD (clean slate)
# Suppress the start center via user.cfg in env, but ensure it starts with Part Design or empty
echo "Starting FreeCAD..."
# We use the generic launch util, but we can also force a specific workbench if needed.
# The task description implies starting from scratch, so just opening FreeCAD is fine.
launch_freecad

# 6. Wait for window and maximize
wait_for_freecad 30
maximize_freecad

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="