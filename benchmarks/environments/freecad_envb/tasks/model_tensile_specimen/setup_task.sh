#!/bin/bash
set -e
echo "=== Setting up ASTM D638 Modeling Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/FreeCAD/tensile_specimen.FCStd
rm -f /tmp/analysis_result.json

# 3. Ensure clean directory exists
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# 4. Kill any running FreeCAD instances
kill_freecad

# 5. Launch FreeCAD with an empty state
# We launch it without a file so the agent starts from scratch
echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 freecad > /tmp/freecad_task.log 2>&1 &"

# 6. Wait for window and maximize
wait_for_freecad 30
maximize_freecad

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="