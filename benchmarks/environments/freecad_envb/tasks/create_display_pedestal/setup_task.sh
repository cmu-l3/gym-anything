#!/bin/bash
set -e
echo "=== Setting up create_display_pedestal task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove any previous output to ensure deterministic start state
rm -f /home/ga/Documents/FreeCAD/display_pedestal.FCStd

# Kill any running FreeCAD instance
pkill -f freecad 2>/dev/null || true
sleep 2

# Launch FreeCAD with a new empty document
# We use a small python script to ensure it starts cleanly with a new doc
cat > /tmp/start_empty.py << PYEOF
import FreeCAD, FreeCADGui
FreeCAD.newDocument("Unnamed")
PYEOF

echo "Starting FreeCAD..."
# Start FreeCAD in background
su - ga -c "DISPLAY=:1 freecad /tmp/start_empty.py > /tmp/freecad_launch.log 2>&1 &"

# Wait for window using utility function
wait_for_freecad 30

# Maximize window for better visibility
maximize_freecad

# Ensure Part workbench is selected (usually default from env setup, but good to be safe)
# We can't easily force workbench via CLI after launch without complex IPC, 
# but the agent knows to switch workbenches.
# We just ensure the window is ready.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="