#!/bin/bash
echo "=== Setting up building_system_grouping task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_fm_groups.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create FM Grouping specification document ──────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/fm_groups_spec.txt << 'SPECEOF'
FM HANDOVER: MAINTENANCE GROUPING SPECIFICATION
===============================================
Project: FZK-Haus Residential Building
Prepared by: CAFM Implementation Team
Date: 2024-03-15

SCOPE
-----
The FZK-Haus IFC model is currently open in BlenderBIM/Bonsai.
Before the model can be imported into the CAFM (Computer-Aided 
Facilities Management) system, elements must be organized into 
logical maintenance groups using IfcGroup.

INSTRUCTIONS
------------
Using Bonsai's 'Groups and Systems' panel (in the Scene properties), 
create the following three maintenance groups and assign the 
specified elements to them:

GROUP 1: "Building Envelope"
  Assign: All External Walls (IfcWall) AND all Windows (IfcWindow)
  Reason: Fabric maintenance, weatherproofing inspections.
  (Note: You may assign ALL walls to this group if external vs 
   internal is indistinguishable).

GROUP 2: "Access and Egress"
  Assign: All Doors (IfcDoor)
  Reason: Door hardware maintenance, fire door checks.

GROUP 3: "Structural Floor System"
  Assign: All Slabs/Floors (IfcSlab)
  Reason: Floor condition surveys, structural load assessments.

DELIVERABLE
-----------
Once all groups are created and elements are assigned, save the 
IFC Project to:
  /home/ga/BIMProjects/fzk_fm_groups.ifc

NOTES:
  - You must use IfcGroup (or IfcSystem).
  - Use Bonsai's "Assign" functionality to add selected elements 
    to the active group.
  - The FZK-Haus contains roughly 13 walls, 5 doors, 11 windows, 
    and 4 slabs.
SPECEOF
chown ga:ga /home/ga/Desktop/fm_groups_spec.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_groups.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for grouping task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for grouping task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_groups.py > /tmp/blender_task.log 2>&1 &"

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
echo "Spec: /home/ga/Desktop/fm_groups_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_fm_groups.ifc"