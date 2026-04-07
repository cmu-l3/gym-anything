#!/bin/bash
echo "=== Setting up elevator_retrofit_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_elevator_retrofit.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender instances ────────────────────────────────
kill_blender

# ── 4. Create project brief specification document ────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/elevator_retrofit_brief.txt << 'SPECEOF'
ELEVATOR RETROFIT SPECIFICATION
===============================
Project:    FZK-Haus Residential Building
Discipline: Accessibility / Architecture
Date:       2024-03-15

SCOPE
-----
The existing FZK-Haus IFC model is currently loaded in BlenderBIM/Bonsai.
It contains stairs but lacks mechanized vertical transport.
Your task is to retrofit a passenger elevator into the model.

REQUIREMENTS
------------
1. ELEVATOR CAR (IfcTransportElement)
   - Model the elevator car geometry (e.g. 1.5m x 1.5m box)
   - IFC Class: IfcTransportElement
   - PredefinedType: ELEVATOR
   - Property: Create a property set and add a property with "Capacity" in its name
     (e.g. "CapacityPeople" = 6, or "MaxCapacity" = 450)

2. LANDING DOORS (IfcDoor)
   - The FZK-Haus currently has exactly 5 doors.
   - You must model at least 2 new landing doors (one for Ground Floor, one for First Floor)
   - IFC Class: IfcDoor
   - Total doors in the model should be at least 7 when finished.

3. SPATIAL CONTAINMENT
   - All newly created elements must be properly contained within the building spatial
     hierarchy (e.g. assigned to the appropriate IfcBuildingStorey).

DELIVERABLE
-----------
Save the updated IFC project to:
/home/ga/BIMProjects/fzk_elevator_retrofit.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/elevator_retrofit_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp (Anti-gaming) ──────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_elevator.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for elevator retrofit task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_elevator.py > /tmp/blender_task.log 2>&1 &"

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

# Extra time for IFC to finish loading
sleep 10

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="