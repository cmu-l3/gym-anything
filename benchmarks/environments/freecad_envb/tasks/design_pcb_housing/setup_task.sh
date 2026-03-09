#!/bin/bash
set -e
echo "=== Setting up design_pcb_housing task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean output directory
mkdir -p /home/ga/Documents/FreeCAD
chown -R ga:ga /home/ga/Documents/FreeCAD

# Remove previous output to ensure clean state
rm -f /home/ga/Documents/FreeCAD/pcb_housing.FCStd

# Kill any running FreeCAD instance
kill_freecad

# Launch FreeCAD with a new empty document
# We use a small startup script to ensure PartDesign workbench is ready
cat > /tmp/start_task.py << PYEOF
import FreeCAD
import FreeCADGui
FreeCADGui.activateWorkbench("PartDesignWorkbench")
FreeCAD.newDocument("PCB_Housing")
PYEOF

echo "Starting FreeCAD..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority freecad /tmp/start_task.py > /tmp/freecad_task.log 2>&1 &"

# Wait for FreeCAD window
wait_for_freecad 30

# Maximize window
maximize_freecad

# Show Combo View (Model Tree)
# Coordinates are approximate for standard FreeCAD layout; using shortcuts if available is safer, 
# but FreeCAD shortcuts vary. We'll rely on the user.cfg setup in env to have panels mostly ready.
# Ensuring window is focused is critical.
DISPLAY=:1 wmctrl -a "FreeCAD" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="