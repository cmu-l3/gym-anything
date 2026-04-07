#!/bin/bash
echo "=== Setting up mep_structural_clash_resolution task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown -R ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing clash models ───────────────────────────────────
rm -f /home/ga/BIMProjects/clash_model.ifc 2>/dev/null || true
rm -f /home/ga/BIMProjects/clash_model_resolved.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender instances ────────────────────────────────
kill_blender

# ── 4. Generate the clash model programmatically using ifcopenshell ───────
echo "Generating standard IFC clash model..."

cat > /tmp/generate_clash_model.py << 'PYEOF'
import sys
import os
import numpy as np

# Use BlenderBIM's bundled ifcopenshell
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

import ifcopenshell
import ifcopenshell.api as api

model = ifcopenshell.file(schema="IFC4")
project = api.run("root.create_entity", model, ifc_class="IfcProject", name="Federated_Coordination_Model")
api.run("unit.assign_unit", model)

# Contexts for geometry
ctx = api.run("context.add_context", model, context_type="Model")
body = api.run("context.add_context", model, context_type="Model", context_identifier="Body", target_view="MODEL_VIEW", parent=ctx)

# Spatial hierarchy
site = api.run("root.create_entity", model, ifc_class="IfcSite", name="Site")
building = api.run("root.create_entity", model, ifc_class="IfcBuilding", name="Building")
storey = api.run("root.create_entity", model, ifc_class="IfcBuildingStorey", name="Ground Floor")
api.run("aggregate.assign_object", model, relating_object=project, product=site)
api.run("aggregate.assign_object", model, relating_object=site, product=building)
api.run("aggregate.assign_object", model, relating_object=building, product=storey)

# Create Primary Beam (Extrudes along Z normally, we'll place it rotated along Y)
beam = api.run("root.create_entity", model, ifc_class="IfcBeam", name="Beam-Primary")
api.run("spatial.assign_container", model, product=beam, relating_structure=storey)
beam_prof = api.run("geometry.add_profile", model, profile_type="AREA", profile_name="BeamProf", profile_expression="IfcRectangleProfileDef", x_dim=0.3, y_dim=0.6)
beam_rep = api.run("geometry.add_extrusion_representation", model, context=body, profile=beam_prof, depth=6.0)
api.run("geometry.assign_representation", model, product=beam, representation=beam_rep)

# Place Beam at (0, -3, 3) pointing along +Y (Rotate 90deg around X)
mat_beam = np.array([
    [1.0,  0.0,  0.0,  0.0],
    [0.0,  0.0, -1.0, -3.0],
    [0.0,  1.0,  0.0,  3.0],
    [0.0,  0.0,  0.0,  1.0]
])
api.run("geometry.edit_object_placement", model, product=beam, matrix=mat_beam)

# Create MEP Duct (Extrudes along Z normally, we'll place it rotated along X)
duct = api.run("root.create_entity", model, ifc_class="IfcDuctSegment", name="Duct-Main")
api.run("spatial.assign_container", model, product=duct, relating_structure=storey)
duct_prof = api.run("geometry.add_profile", model, profile_type="AREA", profile_name="DuctProf", profile_expression="IfcRectangleProfileDef", x_dim=0.5, y_dim=0.5)
duct_rep = api.run("geometry.add_extrusion_representation", model, context=body, profile=duct_prof, depth=6.0)
api.run("geometry.assign_representation", model, product=duct, representation=duct_rep)

# Place Duct at (-3, 0, 3) pointing along +X (Rotate 90deg around Y)
mat_duct = np.array([
    [0.0,  0.0,  1.0, -3.0],
    [0.0,  1.0,  0.0,  0.0],
    [-1.0, 0.0,  0.0,  3.0],
    [0.0,  0.0,  0.0,  1.0]
])
api.run("geometry.edit_object_placement", model, product=duct, matrix=mat_duct)

out_path = "/home/ga/BIMProjects/clash_model.ifc"
model.write(out_path)
print(f"RESULT: Generated clash model at {out_path}")
PYEOF

/opt/blender/blender --background --python /tmp/generate_clash_model.py 2>&1 | grep 'RESULT:'
chown ga:ga /home/ga/BIMProjects/clash_model.ifc

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Blender startup script to auto-load the clash model ─────────
cat > /tmp/load_clash_model.py << 'PYEOF'
import bpy
import sys

def load_clash():
    """Load Clash IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/BIMProjects/clash_model.ifc")
        
        # Optimize view for coordination: Select duct to draw attention
        for obj in bpy.data.objects:
            if obj.name == "Duct-Main":
                obj.select_set(True)
                bpy.context.view_layer.objects.active = obj
                bpy.ops.view3d.view_selected()
        print("Clash model loaded successfully.")
    except Exception as e:
        print(f"Error loading clash model: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_clash, first_interval=3.0)
PYEOF

# ── 7. Launch Blender ─────────────────────────────────────────────────────
echo "Launching Blender with the coordination model..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_clash_model.py > /tmp/blender_task.log 2>&1 &"

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

# Wait for IFC to fully load
sleep 8

# ── 8. Focus, maximize, and take screenshot ───────────────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="