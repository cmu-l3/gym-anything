#!/bin/bash
set -e
echo "=== Setting up model_twisted_pedestal task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove previous output to ensure a fresh start
rm -f /home/ga/Documents/FreeCAD/twisted_pedestal.FCStd

# Kill any running FreeCAD instance
kill_freecad

# Launch FreeCAD with a new empty document
# We use a python script to ensure a clean new doc is ready
cat > /tmp/start_freecad.py << PYEOF
import FreeCAD
import FreeCADGui
FreeCADGui.showMainWindow()
FreeCAD.newDocument("TwistedPedestal")
PYEOF

echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 freecad /tmp/start_freecad.py > /tmp/freecad_launch.log 2>&1 &"

# Wait for window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Ensure Part workbench is loaded (common for lofting)
DISPLAY=:1 xdotool key alt+v p w p Return 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="