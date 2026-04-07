#!/bin/bash
echo "=== Setting up service_penetration_openings task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_mep_openings.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create Penetration Schedule ────────────────────────────────────────
cat > /home/ga/BIMProjects/penetration_schedule.txt << 'SPECEOF'
MEP PENETRATION SCHEDULE
========================
Project:    FZK-Haus Residential Building
Phase:      Coordination / Builders Work in Connection (BWIC)
Date:       2024-10-24

INSTRUCTIONS
------------
Before ductwork and piping can be modeled, service voids (openings)
must be defined in the structural walls. 

For each item below, model a void element of the approximate size 
through any appropriate internal or external wall.
1. Create the mesh geometry
2. Assign it as an IfcOpeningElement
3. Add the opening/void relationship to the host wall

REQUIRED PENETRATIONS
---------------------
| ID    | Purpose               | Host Element | Approx Size (W x H) |
|-------|-----------------------|--------------|---------------------|
| SP-01 | HVAC Supply Duct      | IfcWall      | 600mm x 400mm       |
| SP-02 | HVAC Return Duct      | IfcWall      | 600mm x 400mm       |
| SP-03 | Domestic Water Riser  | IfcWall      | 200mm x 200mm       |
| SP-04 | Waste Water Pipe      | IfcWall      | 150mm x 150mm       |

Save the modified IFC project to:
/home/ga/BIMProjects/fzk_mep_openings.ifc
SPECEOF
chown ga:ga /home/ga/BIMProjects/penetration_schedule.txt
echo "Penetration schedule placed in /home/ga/BIMProjects/"

# ── 5. Record initial state of FZK-Haus ───────────────────────────────────
echo "Recording baseline openings count for FZK-Haus..."
cat > /tmp/record_baseline.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/IFCModels/fzk_haus.ifc"
result = {
    "initial_openings": 0,
    "initial_voids": 0,
    "initial_wall_hosted": 0,
    "initial_with_geom": 0
}

try:
    import ifcopenshell
    ifc = ifcopenshell.open(ifc_path)
    
    openings = list(ifc.by_type("IfcOpeningElement"))
    voids = list(ifc.by_type("IfcRelVoidsElement"))
    
    wall_hosted = 0
    for v in voids:
        host = v.RelatingBuildingElement
        opening = v.RelatedOpeningElement
        if host and opening and host.is_a("IfcWall") and opening.is_a("IfcOpeningElement"):
            wall_hosted += 1
            
    with_geom = 0
    for o in openings:
        if o.Representation and getattr(o.Representation, 'Representations', None):
            if len(o.Representation.Representations) > 0:
                with_geom += 1

    result["initial_openings"] = len(openings)
    result["initial_voids"] = len(voids)
    result["initial_wall_hosted"] = wall_hosted
    result["initial_with_geom"] = with_geom
except Exception as e:
    print(f"Error recording baseline: {e}")

with open("/tmp/initial_opening_counts.json", "w") as f:
    json.dump(result, f)
print("Baseline recorded.")
PYEOF

/opt/blender/blender --background --python /tmp/record_baseline.py > /dev/null 2>&1
chmod 444 /tmp/initial_opening_counts.json # Read-only

# ── 6. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 7. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_openings.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for MEP openings task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 8. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_openings.py > /tmp/blender_task.log 2>&1 &"

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

# ── 9. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus loaded in Bonsai"
echo "Schedule: /home/ga/BIMProjects/penetration_schedule.txt"