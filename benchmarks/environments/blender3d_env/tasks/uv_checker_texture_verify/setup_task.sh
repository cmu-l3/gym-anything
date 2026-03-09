#!/bin/bash
set -e
echo "=== Setting up UV Checker Texture task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean any previous artifacts
rm -f /home/ga/BlenderProjects/suzanne_checker.blend
rm -f /home/ga/BlenderProjects/checker_render.png
rm -f /tmp/task_result.json
rm -f /tmp/initial_state.json

# Ensure project directory exists
mkdir -p /home/ga/BlenderProjects
chown ga:ga /home/ga/BlenderProjects

# Create the Suzanne scene with UV layers stripped
# We use a python script to generate the .blend file programmatically
cat > /tmp/create_suzanne_scene.py << 'PYEOF'
import bpy
import json
import os

# Start fresh
bpy.ops.wm.read_homefile(use_empty=True)

# Add Suzanne (monkey head)
bpy.ops.mesh.primitive_monkey_add(size=2, location=(0, 0, 1.5))
suzanne = bpy.context.active_object
suzanne.name = "Suzanne"

# Apply subdivision for better mesh quality
bpy.ops.object.modifier_add(type='SUBSURF')
suzanne.modifiers["Subdivision"].levels = 2
suzanne.modifiers["Subdivision"].render_levels = 2
bpy.ops.object.modifier_apply(modifier="Subdivision")

# Apply smooth shading
bpy.ops.object.shade_smooth()

# CRITICAL: Remove all UV layers to force agent to unwrap
mesh = suzanne.data
while mesh.uv_layers:
    mesh.uv_layers.remove(mesh.uv_layers[0])

# Add a default grey material (no texture)
mat = bpy.data.materials.new(name="SuzanneMaterial")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1.0)
bsdf.inputs["Roughness"].default_value = 0.5
suzanne.data.materials.append(mat)

# Add ground plane
bpy.ops.mesh.primitive_plane_add(size=10, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
ground_mat = bpy.data.materials.new(name="GroundMaterial")
ground_mat.use_nodes = True
ground_bsdf = ground_mat.node_tree.nodes["Principled BSDF"]
ground_bsdf.inputs["Base Color"].default_value = (0.3, 0.3, 0.35, 1.0)
ground.data.materials.append(ground_mat)

# Add camera aimed at Suzanne
bpy.ops.object.camera_add(location=(4.5, -3.5, 3.0))
camera = bpy.context.active_object
camera.name = "Camera"
# Point camera at Suzanne
bpy.ops.object.constraint_add(type='TRACK_TO')
camera.constraints['Track To'].target = suzanne
camera.constraints['Track To'].track_axis = 'TRACK_NEGATIVE_Z'
camera.constraints['Track To'].up_axis = 'UP_Y'
bpy.context.scene.camera = camera

# Add sun light
bpy.ops.object.light_add(type='SUN', location=(3, 4, 8))
sun = bpy.context.active_object
sun.name = "SunLight"
sun.data.energy = 3.0

# Configure render settings for EEVEE (fast)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'

# Save
output_path = "/home/ga/BlenderProjects/suzanne_no_uv.blend"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=output_path)
print(f"Scene saved to: {output_path}")

# Record initial state
initial_state = {
    "suzanne_uv_layer_count": len(suzanne.data.uv_layers),
    "file_path": output_path
}

with open("/tmp/initial_state.json", "w") as f:
    json.dump(initial_state, f, indent=2)
PYEOF

# Run scene creation
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_suzanne_scene.py" 2>&1 | tail -20

# Verify initial scene was created
if [ ! -f "/home/ga/BlenderProjects/suzanne_no_uv.blend" ]; then
    echo "ERROR: Failed to create initial scene"
    exit 1
fi

# Kill any existing Blender instances
pkill -f blender 2>/dev/null || true
sleep 2

# Launch Blender with the scene
echo "Launching Blender with Suzanne scene..."
su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/suzanne_no_uv.blend &"
sleep 8

# Wait for Blender window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "[Bb]lender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any splash screen (Escape key)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="