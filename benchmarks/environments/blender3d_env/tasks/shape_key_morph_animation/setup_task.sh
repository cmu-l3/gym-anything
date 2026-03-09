#!/bin/bash
set -e
echo "=== Setting up Shape Key Morphing Animation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECTS_DIR="/home/ga/BlenderProjects"
SCENE_FILE="$PROJECTS_DIR/morph_scene.blend"
OUTPUT_FILE="$PROJECTS_DIR/morph_animation.blend"
mkdir -p "$PROJECTS_DIR"
chown -R ga:ga "$PROJECTS_DIR"

# Remove any previous output
rm -f "$OUTPUT_FILE"
rm -f /tmp/task_result.json

# Create the starting scene with a subdivided cube via Blender Python
cat > /tmp/create_morph_scene.py << 'PYEOF'
import bpy
import json
import os

# Start fresh
bpy.ops.wm.read_homefile(use_empty=True)

# ----- MorphCube: subdivided cube -----
# Create cube
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1.5))
cube = bpy.context.active_object
cube.name = "MorphCube"

# Add Subdivision Surface modifier and apply it to get geometry for morphing
mod = cube.modifiers.new(name="Subdiv", type='SUBSURF')
mod.levels = 3
mod.render_levels = 3
bpy.ops.object.modifier_apply(modifier=mod.name)

# Add a simple material
mat = bpy.data.materials.new(name="MorphMaterial")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.1, 0.5, 0.9, 1.0)
bsdf.inputs["Roughness"].default_value = 0.3
cube.data.materials.append(mat)

# ----- Camera -----
bpy.ops.object.camera_add(location=(6, -5, 4))
camera = bpy.context.active_object
camera.name = "MainCamera"
# Point at the cube
bpy.ops.object.constraint_add(type='TRACK_TO')
camera.constraints['Track To'].target = cube
camera.constraints['Track To'].track_axis = 'TRACK_NEGATIVE_Z'
camera.constraints['Track To'].up_axis = 'UP_Y'
bpy.context.scene.camera = camera

# ----- Sun Light -----
bpy.ops.object.light_add(type='SUN', location=(4, 4, 8))
sun = bpy.context.active_object
sun.name = "SunLight"
sun.data.energy = 3.0

# ----- Ground Plane -----
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"

# ----- Render Settings -----
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 50 
scene.frame_start = 1
scene.frame_end = 250

# Ensure no shape keys exist initially
if cube.data.shape_keys:
    cube.active_shape_key_index = 0
    bpy.ops.object.shape_key_remove(all=True)

# Save scene
output_path = "/home/ga/BlenderProjects/morph_scene.blend"
bpy.ops.wm.save_as_mainfile(filepath=output_path)
print(f"Scene saved to {output_path}")
PYEOF

echo "Generating starting scene..."
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_morph_scene.py" 2>&1 | tail -5

# Ensure permissions
chown ga:ga "$SCENE_FILE"

# Launch Blender
if ! pgrep -f "blender" > /dev/null; then
    echo "Launching Blender..."
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$SCENE_FILE' &"
    sleep 10
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="