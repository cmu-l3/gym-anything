#!/bin/bash
echo "=== Setting up structural_steel_profile_detailing task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output/scaffold files ──────────────────────────
rm -f /home/ga/BIMProjects/steel_portal_frame.ifc 2>/dev/null || true
rm -f /home/ga/BIMProjects/warehouse_baseline.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Build the scaffold baseline IFC model using ifcopenshell ───────────
echo "Creating baseline IFC model..."

cat > /tmp/create_baseline_model.py << 'PYEOF'
import sys
import os
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

import ifcopenshell
import ifcopenshell.api as api

model = ifcopenshell.file(schema="IFC4")

# Spatial hierarchy
project = api.run("root.create_entity", model, ifc_class="IfcProject", name="Warehouse Steel Frame")
site = api.run("root.create_entity", model, ifc_class="IfcSite", name="Industrial Park")
building = api.run("root.create_entity", model, ifc_class="IfcBuilding", name="Warehouse A")
storey = api.run("root.create_entity", model, ifc_class="IfcBuildingStorey", name="Ground Floor")

api.run("aggregate.assign_object", model, relating_object=project, product=site)
api.run("aggregate.assign_object", model, relating_object=site, product=building)
api.run("aggregate.assign_object", model, relating_object=building, product=storey)

# Create Foundation Slab
slab = api.run("root.create_entity", model, ifc_class="IfcSlab", name="Foundation Slab")
api.run("spatial.assign_container", model, product=slab, relating_structure=storey)

out_path = "/home/ga/BIMProjects/warehouse_baseline.ifc"
model.write(out_path)
print(f"RESULT:Baseline model written to {out_path}")
PYEOF

/opt/blender/blender --background --python /tmp/create_baseline_model.py 2>&1 | grep 'RESULT:'

if [ ! -f /home/ga/BIMProjects/warehouse_baseline.ifc ]; then
    echo "ERROR: Failed to create baseline IFC model"
    exit 1
fi
chown ga:ga /home/ga/BIMProjects/warehouse_baseline.ifc
echo "Baseline model created: /home/ga/BIMProjects/warehouse_baseline.ifc"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load the baseline ──────────────
cat > /tmp/load_baseline.py << 'PYEOF'
import bpy
import sys

def load_warehouse():
    """Load baseline IFC into Bonsai."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/BIMProjects/warehouse_baseline.ifc")
        print("Warehouse baseline loaded")
    except Exception as e:
        print(f"Error loading baseline: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_warehouse, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with warehouse baseline..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_baseline.py > /tmp/blender_task.log 2>&1 &"

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

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Warehouse baseline loaded."
echo "Expected output: /home/ga/BIMProjects/steel_portal_frame.ifc"