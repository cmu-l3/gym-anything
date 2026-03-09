#!/bin/bash
set -e
echo "=== Setting up Cloth Drape Simulation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Remove any previous outputs to ensure clean state
rm -f "$PROJECTS_DIR/cloth_drape.blend"
rm -f "$PROJECTS_DIR/cloth_render.png"

# Create the initial table scene via Blender Python
# This ensures a consistent starting geometry for the physics task
cat > /tmp/create_table_scene.py << 'SCENE_EOF'
import bpy
import math

# Clear everything
bpy.ops.wm.read_homefile(use_empty=True)

# --- Table Top ---
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1.0))
table_top = bpy.context.active_object
table_top.name = "TableTop"
table_top.scale = (1.5, 1.0, 0.05)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# Table material
mat_table = bpy.data.materials.new(name="TableMaterial")
mat_table.use_nodes = True
bsdf = mat_table.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.35, 0.2, 0.1, 1.0)  # Dark wood
bsdf.inputs["Roughness"].default_value = 0.4
table_top.data.materials.append(mat_table)

# --- Table Legs (4 cylinders) ---
leg_positions = [(1.2, 0.7, 0.475), (-1.2, 0.7, 0.475), (1.2, -0.7, 0.475), (-1.2, -0.7, 0.475)]
for i, pos in enumerate(leg_positions):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=0.95, location=pos)
    leg = bpy.context.active_object
    leg.name = f"TableLeg.{i+1}"
    leg.data.materials.append(mat_table)

# --- Ground Plane ---
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
mat_ground = bpy.data.materials.new(name="GroundMaterial")
mat_ground.use_nodes = True
bsdf_g = mat_ground.node_tree.nodes["Principled BSDF"]
bsdf_g.inputs["Base Color"].default_value = (0.6, 0.6, 0.55, 1.0)
bsdf_g.inputs["Roughness"].default_value = 0.8
ground.data.materials.append(mat_ground)

# --- Camera ---
bpy.ops.object.camera_add(location=(4.5, -3.5, 3.0))
camera = bpy.context.active_object
camera.name = "Camera"
# Point camera at table
camera.rotation_euler = (math.radians(55), 0, math.radians(50))
bpy.context.scene.camera = camera

# --- Sun Light ---
bpy.ops.object.light_add(type='SUN', location=(3, 4, 8))
sun = bpy.context.active_object
sun.name = "SunLight"
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(40), math.radians(15), math.radians(-20))

# --- Render Settings ---
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 960
scene.render.resolution_y = 540
scene.render.resolution_percentage = 100
scene.cycles.samples = 32
scene.cycles.use_denoising = True
# Use CPU (reliable in CI environments)
scene.cycles.device = 'CPU'

# Frame range at defaults
scene.frame_start = 1
scene.frame_end = 250
scene.frame_current = 1

# --- World background ---
world = bpy.data.worlds.new(name="World")
bpy.context.scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.85, 0.85, 0.9, 1.0)  # Light grey-blue
bg.inputs["Strength"].default_value = 0.5

# Save the scene
output_path = "/home/ga/BlenderProjects/table_scene.blend"
bpy.ops.wm.save_as_mainfile(filepath=output_path)
print(f"Table scene saved to: {output_path}")
SCENE_EOF

# Run the scene creation headlessly
echo "Generating starting scene..."
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_table_scene.py" 2>&1 | tail -5

# Record initial state for anti-gaming comparison
cat > /tmp/record_initial_state.py << 'STATE_EOF'
import bpy
import json

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/table_scene.blend")

state = {
    "object_count": len(bpy.data.objects),
    "objects": [],
    "has_cloth_physics": False,
    "has_collision_physics": False
}

for obj in bpy.data.objects:
    obj_info = {
        "name": obj.name,
        "type": obj.type,
        "has_cloth": any(m.type == 'CLOTH' for m in obj.modifiers),
        "has_collision": any(m.type == 'COLLISION' for m in obj.modifiers)
    }
    state["objects"].append(obj_info)
    if obj_info["has_cloth"]:
        state["has_cloth_physics"] = True
    if obj_info["has_collision"]:
        state["has_collision_physics"] = True

print("INITIAL_STATE:" + json.dumps(state))
STATE_EOF

su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/record_initial_state.py" > /tmp/initial_state_log.txt 2>&1

# Extract JSON from log
grep "INITIAL_STATE:" /tmp/initial_state_log.txt | sed 's/INITIAL_STATE://' > /tmp/initial_state.json

# Launch Blender with the table scene
echo "Launching Blender with table scene..."
if ! pgrep -x "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/table_scene.blend &"
fi

# Wait for Blender window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus (Critical for VLM)
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Dismiss any splash screen/popups
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Cloth Drape Simulation task setup complete ==="