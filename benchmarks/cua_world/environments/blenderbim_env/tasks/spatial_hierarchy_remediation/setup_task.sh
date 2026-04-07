#!/bin/bash
echo "=== Setting up spatial_hierarchy_remediation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure directories exist ───────────────────────────────────────────
mkdir -p /home/ga/BIMProjects
mkdir -p /home/ga/IFCModels
chown ga:ga /home/ga/BIMProjects /home/ga/IFCModels

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_repaired.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the flattened / corrupted IFC model ─────────────────────────
echo "Creating flattened IFC model from FZK-Haus..."

cat > /tmp/create_flat_model.py << 'PYEOF'
import sys
import os

# Ensure Bonsai's ifcopenshell is available
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

import ifcopenshell

def flatten_model():
    in_path = "/home/ga/IFCModels/fzk_haus.ifc"
    out_path = "/home/ga/IFCModels/fzk_flat.ifc"
    
    if not os.path.exists(in_path):
        print(f"RESULT:Error: {in_path} not found.")
        return

    try:
        ifc = ifcopenshell.open(in_path)
        building = ifc.by_type("IfcBuilding")[0]
        storeys = ifc.by_type("IfcBuildingStorey")

        # Collect all building elements currently in spatial structures
        elements = set()
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            for el in rel.RelatedElements:
                elements.add(el)
        
        # Remove all existing spatial containment relationships
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            ifc.remove(rel)

        # Create a single spatial containment linking everything directly to the IfcBuilding
        if elements:
            ifc.createIfcRelContainedInSpatialStructure(
                GlobalId=ifcopenshell.guid.new(),
                RelatingStructure=building,
                RelatedElements=list(elements)
            )

        # Remove decomposition relations for storeys
        for rel in ifc.by_type("IfcRelAggregates"):
            if rel.RelatingObject == building:
                # Filter out storeys from RelatedObjects
                new_related = [obj for obj in rel.RelatedObjects if not obj.is_a("IfcBuildingStorey")]
                if new_related:
                    rel.RelatedObjects = new_related
                else:
                    ifc.remove(rel)

        # Remove the storeys entirely
        for s in storeys:
            ifc.remove(s)

        ifc.write(out_path)
        print(f"RESULT:Success - Flat model written to {out_path} with {len(elements)} elements in building.")
    except Exception as e:
        print(f"RESULT:Error flattening model: {e}")

flatten_model()
PYEOF

/opt/blender/blender --background --python /tmp/create_flat_model.py 2>&1 | grep 'RESULT:'

if [ ! -f /home/ga/IFCModels/fzk_flat.ifc ]; then
    echo "ERROR: Failed to create corrupted IFC model"
    exit 1
fi
chown ga:ga /home/ga/IFCModels/fzk_flat.ifc
echo "Corrupted flat model created: /home/ga/IFCModels/fzk_flat.ifc"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load the corrupted model ───────
cat > /tmp/load_flat_model.py << 'PYEOF'
import bpy
import sys

def load_fzk_flat():
    """Load the corrupted flat IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_flat.ifc")
        print("Flat FZK-Haus IFC loaded successfully for remediation task")
    except Exception as e:
        print(f"Error loading model: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_flat, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with flat FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_flat_model.py > /tmp/blender_task.log 2>&1 &"

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

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Corrupted model should now be loaded in Bonsai"
echo "Expected output: /home/ga/BIMProjects/fzk_repaired.ifc"