#!/bin/bash
set -e
echo "=== Setting up apply_hatch_pattern task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure the workspace directory exists and has permissions
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Ensure the real floor plan is available
if [ ! -f /home/ga/Documents/LibreCAD/floorplan.dxf ]; then
    echo "Restoring floorplan.dxf from samples..."
    cp /opt/librecad_samples/floorplan.dxf /home/ga/Documents/LibreCAD/floorplan.dxf
fi
chown ga:ga /home/ga/Documents/LibreCAD/floorplan.dxf

# Record initial entity count for anti-gaming (to prove new stuff was added)
# Using python/ezdxf inside container since it is installed in the environment
python3 -c "
import ezdxf
try:
    doc = ezdxf.readfile('/home/ga/Documents/LibreCAD/floorplan.dxf')
    msp = doc.modelspace()
    print(len(list(msp)))
except:
    print('0')
" > /tmp/initial_entity_count.txt 2>/dev/null || echo "0" > /tmp/initial_entity_count.txt

# Remove any previous output file to ensure clean state
rm -f /home/ga/Documents/LibreCAD/floorplan_hatched.dxf

# Kill any existing LibreCAD instances
pkill -f librecad 2>/dev/null || true
sleep 2

# Launch LibreCAD with the floorplan file
echo "Launching LibreCAD..."
su - ga -c "DISPLAY=:1 librecad /home/ga/Documents/LibreCAD/floorplan.dxf > /tmp/librecad_task.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "LibreCAD|floorplan"; then
        echo "LibreCAD window detected"
        break
    fi
    sleep 1
done

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs (like Tip of the Day)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="