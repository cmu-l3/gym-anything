#!/bin/bash
echo "=== Setting up interior_covering_specification task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure directories exist ───────────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_interior_finishes.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the interior fit-out spec document on Desktop ───────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/interior_fitout_spec.txt << 'SPECEOF'
INTERIOR FIT-OUT SPECIFICATION
==============================
Project:    FZK-Haus Residential Fit-out
Client:     FZK Properties Ltd
Ref:        INT-SPEC-2024-001
Date:       2024-03-15

SCOPE
-----
The structural shell (walls, slabs, doors, windows) of the
FZK-Haus is already modelled. You must overlay the interior
finish elements (ceilings and floors) as IfcCovering entities.

REQUIREMENTS
------------
Using BlenderBIM/Bonsai, create the following finish elements
and assign the corresponding materials.

1. CEILING FINISHES
   - Model at least 3 ceiling elements
   - IFC Class: IfcCovering
   - PredefinedType: CEILING
   - Material to create & assign: "Gypsum Plasterboard 12.5mm"
     (or any material containing "Gypsum" or "Plasterboard")

2. FLOOR FINISHES
   - Model at least 3 floor elements
   - IFC Class: IfcCovering
   - PredefinedType: FLOORING
   - Material to create & assign: "Oak Hardwood 20mm"
     (or any material containing "Oak", "Timber", "Hardwood", or "Parquet")

MATERIAL ASSIGNMENT
-------------------
The materials must be explicitly assigned to the covering elements
so they are recorded in the IFC file (IfcRelAssociatesMaterial).

DELIVERABLE
-----------
Save the complete model with your new finish elements to:
/home/ga/BIMProjects/fzk_interior_finishes.ifc

Note: Ensure you use Bonsai's 'Save IFC Project' command.
SPECEOF
chown ga:ga /home/ga/Desktop/interior_fitout_spec.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_coverings.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for the covering task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for interior covering task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_coverings.py > /tmp/blender_task.log 2>&1 &"

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
echo "Spec: /home/ga/Desktop/interior_fitout_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_interior_finishes.ifc"