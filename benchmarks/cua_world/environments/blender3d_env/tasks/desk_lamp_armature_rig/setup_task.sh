#!/bin/bash
set -e
echo "=== Setting up Desk Lamp Armature Rig task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Clean up previous run
rm -f "$PROJECTS_DIR/lamp_rigged.blend"
rm -f /tmp/task_result.json
rm -f /tmp/initial_state.json

# ============================================================
# GENERATE LAMP SCENE VIA PYTHON
# ============================================================
# This script creates the lamp geometry without an armature
cat > /tmp/create_lamp_scene.py << 'PYEOF'
import bpy
import math
import json
import os

# Clear default scene
bpy.ops.wm.read_homefile(use_empty=True)

# Helper to create material
def create_mat(name, color, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat

mat_base = create_mat("BlackMetal", (0.1, 0.1, 0.1, 1.0), 0.8, 0.4)
mat_arm = create_mat("SilverArm", (0.8, 0.8, 0.8, 1.0), 0.9, 0.2)
mat_head = create_mat("RedPaint", (0.8, 0.1, 0.1, 1.0), 0.2, 0.3)
mat_bulb = create_mat("Bulb", (1.0, 1.0, 0.9, 1.0), 0.0, 0.1)

# 1. Lamp Base
bpy.ops.mesh.primitive_cylinder_add(radius=0.4, depth=0.1, location=(0, 0, 0.05))
base = bpy.context.active_object
base.name = "LampBase"
base.data.materials.append(mat_base)

# 2. Lower Arm
bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=1.0, location=(0, 0, 0.6))
lower = bpy.context.active_object
lower.name = "LampLowerArm"
lower.data.materials.append(mat_arm)

# 3. Upper Arm (Angled)
# Pivot point logic is simplified here by just placing it
bpy.ops.mesh.primitive_cylinder_add(radius=0.035, depth=0.8, location=(0, 0.3, 1.4))
upper = bpy.context.active_object
upper.name = "LampUpperArm"
upper.rotation_euler = (math.radians(45), 0, 0)
upper.data.materials.append(mat_arm)

# 4. Lamp Head
bpy.ops.mesh.primitive_cone_add(radius1=0.25, radius2=0.1, depth=0.4, location=(0, 0.6, 1.9))
head = bpy.context.active_object
head.name = "LampHead"
head.rotation_euler = (math.radians(135), 0, 0)
head.data.materials.append(mat_head)

# Add a floor
bpy.ops.mesh.primitive_plane_add(size=10, location=(0, 0, 0))
floor = bpy.context.active_object
floor.name = "Floor"

# Add Camera
bpy.ops.object.camera_add(location=(3, -3, 2))
cam = bpy.context.active_object
cam.name = "Camera"
# Point at lamp
bpy.ops.object.constraint_add(type='TRACK_TO')
cam.constraints["Track To"].target = lower
cam.constraints["Track To"].track_axis = 'TRACK_NEGATIVE_Z'
cam.constraints["Track To"].up_axis = 'UP_Y'
bpy.context.scene.camera = cam

# Add Light
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))

# Save
output_path = "/home/ga/BlenderProjects/lamp_scene.blend"
bpy.ops.wm.save_as_mainfile(filepath=output_path)

# Record initial state
state = {
    "armature_count": len([o for o in bpy.data.objects if o.type == 'ARMATURE']),
    "mesh_names": [o.name for o in bpy.data.objects if o.type == 'MESH']
}
with open("/tmp/initial_state.json", "w") as f:
    json.dump(state, f)
PYEOF

# Run generation script
echo "Generating lamp scene..."
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_lamp_scene.py"

# Launch Blender with the generated scene
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/lamp_scene.blend &"

# Wait for Blender to start
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
maximize_blender
sleep 1
focus_blender
sleep 1

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="