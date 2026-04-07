#!/bin/bash
echo "=== Setting up plumbing_fixture_coordination task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file to avoid false positives
rm -f /home/ga/BIMProjects/fzk_plumbing.ifc 2>/dev/null || true

# 3. Kill any existing Blender instances
kill_blender

# 4. Create task specification document on Desktop (for realism)
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/plumbing_spec.txt << 'SPECEOF'
PLUMBING FIXTURE SPECIFICATION
==============================
Project: FZK-Haus
Deliverable: /home/ga/BIMProjects/fzk_plumbing.ifc

REQUIRED FIXTURES
-----------------
Add 3 placeholder geometries in the Upper Floor bathroom and classify them as follows:

1. Toilet: 
   Class: IfcSanitaryTerminal
   PredefinedType: WCSEAT or TOILETPAN

2. Sink: 
   Class: IfcSanitaryTerminal
   PredefinedType: WASHHANDBASIN or SINK

3. Shower/Bath: 
   Class: IfcSanitaryTerminal
   PredefinedType: BATH or SHOWER

SPATIAL ASSIGNMENT
------------------
Ensure all are spatially contained in the "Obergeschoss" (Upper Floor) building storey.
SPECEOF
chown ga:ga /home/ga/Desktop/plumbing_spec.txt

# 5. Record task start timestamp for anti-gaming
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load FZK-Haus
cat > /tmp/load_fzk_plumbing.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for plumbing coordination task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 7. Launch Blender with startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_plumbing.py > /tmp/blender_task.log 2>&1 &"

# Wait for Blender window
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 15 ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "blender" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Blender window detected: $WID"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Extra time for IFC to load
sleep 10

# 8. Focus, maximize, dismiss dialogs, screenshot
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="