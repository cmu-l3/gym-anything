#!/bin/bash
echo "=== Setting up construction_site_logistics task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure directories exist ───────────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_site_logistics.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create project brief specification document ────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/site_logistics_brief.txt << 'SPECEOF'
SITE LOGISTICS PLANNING BRIEF
=============================
Project:    FZK-Haus Residential Development
Role:       Construction Planner
Date:       2024-03-15

SCOPE
-----
Prepare a preliminary 3D site logistics model using Bonsai in BlenderBIM. 
The main building model (FZK-Haus) is pre-loaded. You need to model 
temporary site elements, classify them correctly, and group them.

DELIVERABLES & REQUIREMENTS
---------------------------
1. TOWER CRANE
   - Model the crane (geometry can be simple boxes/cylinders representing mast/jib).
   - Classify as: IfcTransportElement
   - PredefinedType must be set to: CRANE

2. CRANE SWING RADIUS
   - Model a circular constraint zone showing the crane's operational reach.
   - Classify as: IfcBuildingElementProxy (or IfcSpace)
   - Name attribute MUST be: "Crane Swing Radius"

3. SITE HOARDING
   - Model a perimeter fence around the site.
   - Must consist of at least 4 distinct elements (e.g. 4 fence segments).
   - Classify as: IfcBuildingElementProxy or IfcWall

4. LOGISTICS GROUPING
   - Create a logical group (IfcGroup).
   - Name the group EXACTLY: "Site Logistics"
   - Add the Tower Crane, the Swing Radius, and the 4+ Hoarding elements into this group.

5. EXPORT
   - Save the IFC project to:
     /home/ga/BIMProjects/fzk_site_logistics.ifc

NOTE: Do not overwrite the original fzk_haus.ifc file. Ensure you use Bonsai's 
native 'Save Project' function to output the IFC file.
SPECEOF
chown ga:ga /home/ga/Desktop/site_logistics_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_logistics.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for logistics task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_logistics.py > /tmp/blender_task.log 2>&1 &"

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

# Extra time for IFC to load completely
sleep 10

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should now be loaded in Bonsai"
echo "Brief document: /home/ga/Desktop/site_logistics_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_site_logistics.ifc"