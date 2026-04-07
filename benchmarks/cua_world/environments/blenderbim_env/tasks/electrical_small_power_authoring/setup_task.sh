#!/bin/bash
echo "=== Setting up electrical_small_power_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_electrical.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create electrical brief specification document ─────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/electrical_brief.txt << 'SPECEOF'
ELECTRICAL SMALL POWER LAYOUT BRIEF
=====================================
Project:    FZK-Haus Residential Building
Discipline: Electrical Engineering (MEP)
Date:       2024-03-15

SCOPE
-----
The FZK-Haus IFC model is currently open in BlenderBIM/Bonsai.
The model contains architectural elements but lacks electrical
services. You need to author the initial small power layout.

TASK REQUIREMENTS
-----------------

1. DISTRIBUTION BOARD (IfcDistributionBoard)
   - Create one distribution board (consumer unit) on the ground floor.
   - IFC Type: IfcDistributionBoard

2. SOCKET OUTLETS (IfcOutlet)
   - Create at least four (4) electrical socket outlets on the walls
     in the main living area on the ground floor.
   - IFC Type: IfcOutlet

3. ELECTRICAL CIRCUIT SYSTEM (IfcSystem / IfcDistributionSystem)
   - Create a new logical system in the project named "Power Circuit 1".
   - Assign the newly created Distribution Board to this system.
   - Assign all four Socket Outlets to this system.
   - (In Bonsai, use the Scene Properties -> Systems or MEP grouping tools)

DELIVERABLE
-----------
Save the project (using Bonsai's 'Save Project' function, not
Blender's native save) to the following path:
/home/ga/BIMProjects/fzk_electrical.ifc

NOTE: Geometric precision is secondary. The priority is correct IFC
element types and the topological relationships linking the elements
into a functional circuit (IfcRelAssignsToGroup).
SPECEOF
chown ga:ga /home/ga/Desktop/electrical_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_electrical.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for MEP task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for electrical modeling task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_electrical.py > /tmp/blender_task.log 2>&1 &"

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
sleep 10

# ── 8. Focus, maximize, screenshot ────────────────────────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai"
echo "Spec: /home/ga/Desktop/electrical_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_electrical.ifc"