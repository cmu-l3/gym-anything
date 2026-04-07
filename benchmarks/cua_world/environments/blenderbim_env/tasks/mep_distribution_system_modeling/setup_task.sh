#!/bin/bash
echo "=== Setting up mep_distribution_system_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_mep_services.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create MEP brief specification ─────────────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/mep_coordination_brief.txt << 'SPECEOF'
MEP SERVICES COORDINATION BRIEF
===============================
Project:    FZK-Haus Residential Building
Discipline: Mechanical, Electrical, Plumbing (MEP)
Date:       2024-03-15

OVERVIEW
--------
The architectural IFC model is open in BlenderBIM/Bonsai. 
Before the first coordination clash-detection meeting, you must model 
the primary MEP service routes into the IFC project.

TASK REQUIREMENTS
-----------------
Using Bonsai, model the following elements and group them into 
distribution systems.

1. HVAC SUPPLY AIR
   - Create at least 3 duct segments.
   - IFC Class: IfcDuctSegment
   - Assign these to a new distribution system named "HVAC Supply Air"
     (IFC Class: IfcDistributionSystem).

2. DOMESTIC COLD WATER
   - Create at least 3 plumbing pipe segments.
   - IFC Class: IfcPipeSegment
   - Assign these to a new distribution system named "Domestic Cold Water"
     (IFC Class: IfcDistributionSystem).

GROUP ASSIGNMENT
----------------
Creating the elements and systems is not enough. You must use Bonsai's 
System/Group tools to assign the elements to their respective systems 
so that IFC relationships (IfcRelAssignsToGroup) are established.

PRESERVATION
------------
Do NOT modify or delete the original architectural elements (walls, 
slabs, etc.).

DELIVERABLE
-----------
Save the updated model using 'Save IFC Project' to:
/home/ga/BIMProjects/fzk_mep_services.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/mep_coordination_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_mep.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for MEP task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for MEP coordination task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_mep.py > /tmp/blender_task.log 2>&1 &"

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
echo "Brief: /home/ga/Desktop/mep_coordination_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_mep_services.ifc"