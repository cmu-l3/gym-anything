#!/bin/bash
echo "=== Setting up qto_base_quantities task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_qto_enriched.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create QTO Brief Specification Document ────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/qto_measurement_brief.txt << 'SPECEOF'
QUANTITY TAKE-OFF (QTO) MEASUREMENT BRIEF
=========================================
Project:    FZK-Haus Residential Building
Role:       Junior Quantity Surveyor
Date:       2024-03-15

SCOPE
-----
The FZK-Haus IFC model is open in BlenderBIM/Bonsai. The model 
contains no base quantity data. Before the senior estimator can 
price the model, you must attach standard IFC quantity sets 
(Qto_*BaseQuantities) to the elements.

TASK INSTRUCTIONS
-----------------
Using Bonsai's Object Properties > Quantities tools, add the 
correct quantity sets and populate them with reasonable non-zero 
values. Approximate values are acceptable for this exercise.

1. WALLS (There are 13 walls in the model)
   - Select at least 4 walls
   - Add Quantity Set: Qto_WallBaseQuantities
   - Add quantities such as Length, Height, Width, GrossSideArea
   - (Typical values: Length 4-10m, Height 2.7m, Width 0.3m)

2. DOORS (There are 5 doors in the model)
   - Select at least 2 doors
   - Add Quantity Set: Qto_DoorBaseQuantities
   - Add quantities such as Height, Width, Area
   - (Typical values: Height 2.1m, Width 0.9m)

3. WINDOWS (There are 11 windows in the model)
   - Select at least 2 windows
   - Add Quantity Set: Qto_WindowBaseQuantities
   - Add quantities such as Height, Width, Area
   - (Typical values: Height 1.2m, Width 1.5m)

4. SLABS (There are 4 slabs/floors in the model)
   - Select at least 1 slab
   - Add Quantity Set: Qto_SlabBaseQuantities
   - Add quantities such as GrossArea, Width (thickness), GrossVolume
   - (Typical values: Area 60-80m2, Width 0.3m)

REQUIRED OUTPUT
---------------
Save the completed model using Bonsai's 'Save Project As' to:
/home/ga/BIMProjects/fzk_qto_enriched.ifc

NOTES:
- Names are case-sensitive (e.g., Qto_WallBaseQuantities)
- Ensure you are creating Quantity Sets (IfcElementQuantity), 
  not Property Sets (IfcPropertySet).
SPECEOF
chown ga:ga /home/ga/Desktop/qto_measurement_brief.txt
echo "Measurement brief placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create clean FZK-Haus with NO pre-existing quantities ──────────────
cat > /tmp/clean_fzk.py << 'PYEOF'
import sys
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')
import ifcopenshell

try:
    fzk = ifcopenshell.open("/home/ga/IFCModels/fzk_haus.ifc")
    # Remove any existing IfcElementQuantity relationships
    for rel in fzk.by_type("IfcRelDefinesByProperties"):
        pdef = rel.RelatingPropertyDefinition
        if pdef and pdef.is_a("IfcElementQuantity"):
            fzk.remove(rel)
    # Remove the quantity entities themselves
    for q in fzk.by_type("IfcElementQuantity"):
        fzk.remove(q)
    fzk.write("/tmp/fzk_clean.ifc")
    print("Cleaned FZK-Haus created at /tmp/fzk_clean.ifc")
except Exception as e:
    print(f"Error cleaning FZK-Haus: {e}")
PYEOF

/opt/blender/blender --background --python /tmp/clean_fzk.py > /dev/null 2>&1
chown ga:ga /tmp/fzk_clean.ifc

# ── 7. Create Python startup script to pre-load clean FZK-Haus ────────────
cat > /tmp/load_fzk_qto.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load Cleaned FZK-Haus IFC into Bonsai."""
    try:
        bpy.ops.bim.load_project(filepath="/tmp/fzk_clean.ifc")
        print("Cleaned FZK-Haus loaded for QTO task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 8. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_qto.py > /tmp/blender_task.log 2>&1 &"

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
echo "FZK-Haus should be loaded in Bonsai without existing quantities"
echo "Brief: /home/ga/Desktop/qto_measurement_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_qto_enriched.ifc"