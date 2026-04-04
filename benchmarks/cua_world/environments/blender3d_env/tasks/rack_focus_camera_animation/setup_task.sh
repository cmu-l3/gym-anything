#!/bin/bash
set -e
echo "=== Setting up Rack Focus Camera Animation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/BlenderProjects/rack_focus.blend
rm -f /home/ga/BlenderProjects/rack_focus_frame01.png
rm -f /home/ga/BlenderProjects/rack_focus_frame60.png
rm -f /tmp/task_result.json
rm -f /tmp/initial_state.json

# Ensure projects directory exists
mkdir -p /home/ga/BlenderProjects
chown -R ga:ga /home/ga/BlenderProjects

# Create the rack focus scene using Blender Python
# We create a scene with specific geometry to test focus distances
cat > /tmp/create_rack_focus_scene.py << 'PYEOF'
import bpy
import math
import json
import os

# Clear everything
bpy.ops.wm.read_homefile(use_empty=True)

# ---- Ground Plane ----
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
mat_ground = bpy.data.materials.new(name="GroundMaterial")
mat_ground.use_nodes = True
bsdf_ground = mat_ground.node_tree.nodes["Principled BSDF"]
bsdf_ground.inputs["Base Color"].default_value = (0.35, 0.35, 0.35, 1.0)
bsdf_ground.inputs["Roughness"].default_value = 0.8
ground.data.materials.append(mat_ground)

# ---- Foreground Object: Red Cone (Distance ~4m from camera) ----
# Camera at -8y, Cone at -4y -> dist = 4m
bpy.ops.mesh.primitive_cone_add(radius1=0.6, radius2=0.0, depth=1.5, location=(0, -4, 0.75))
fg_obj = bpy.context.active_object
fg_obj.name = "ForegroundObject"
mat_red = bpy.data.materials.new(name="RedMaterial")
mat_red.use_nodes = True
bsdf_red = mat_red.node_tree.nodes["Principled BSDF"]
bsdf_red.inputs["Base Color"].default_value = (0.85, 0.08, 0.05, 1.0)
bsdf_red.inputs["Roughness"].default_value = 0.3
fg_obj.data.materials.append(mat_red)

# ---- Background Object: Blue Torus (Distance ~12m from camera) ----
# Camera at -8y, Torus at +4y -> dist = 12m
bpy.ops.mesh.primitive_torus_add(
    align='WORLD',
    location=(0, 4, 1),
    major_radius=0.8,
    minor_radius=0.25
)
bg_obj = bpy.context.active_object
bg_obj.name = "BackgroundObject"
mat_blue = bpy.data.materials.new(name="BlueMaterial")
mat_blue.use_nodes = True
bsdf_blue = mat_blue.node_tree.nodes["Principled BSDF"]
bsdf_blue.inputs["Base Color"].default_value = (0.05, 0.15, 0.85, 1.0)
bsdf_blue.inputs["Roughness"].default_value = 0.2
bg_obj.data.materials.append(mat_blue)

# ---- Camera ----
# Positioned at y=-8
bpy.ops.object.camera_add(location=(0, -8, 1.5))
camera = bpy.context.active_object
camera.name = "RackFocusCam"

# Point camera toward (0, 0, 1) using Track To constraint
bpy.ops.object.constraint_add(type='TRACK_TO')
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 1))
aim_target = bpy.context.active_object
aim_target.name = "CameraAimPoint"
aim_target.hide_viewport = True
aim_target.hide_render = True

bpy.context.view_layer.objects.active = camera
camera.select_set(True)
camera.constraints['Track To'].target = aim_target
camera.constraints['Track To'].track_axis = 'TRACK_NEGATIVE_Z'
camera.constraints['Track To'].up_axis = 'UP_Y'

# Set as scene camera
bpy.context.scene.camera = camera

# IMPORTANT: DOF is DISABLED initially (agent must enable it)
camera.data.dof.use_dof = False
camera.data.dof.aperture_fstop = 5.6
camera.data.dof.focus_distance = 10.0
camera.data.lens = 85  # 85mm portrait lens to make DOF more apparent

# ---- Lighting ----
bpy.ops.object.light_add(type='SUN', location=(5, -3, 8))
sun = bpy.context.active_object
sun.name = "SunLight"
sun.data.energy = 4.0
sun.rotation_euler = (math.radians(45), math.radians(15), math.radians(-30))

bpy.ops.object.light_add(type='AREA', location=(-3, -6, 3))
fill = bpy.context.active_object
fill.name = "FillLight"
fill.data.energy = 50.0
fill.data.size = 3.0

# ---- Render Settings ----
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
# Low res for fast agent rendering
scene.render.resolution_x = 960
scene.render.resolution_y = 540
scene.render.resolution_percentage = 100
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.image_settings.file_format = 'PNG'

# Frame range defaults
scene.frame_start = 1
scene.frame_end = 250
scene.frame_current = 1

# Save
output_path = "/home/ga/BlenderProjects/rack_focus_scene.blend"
bpy.ops.wm.save_as_mainfile(filepath=output_path)

# Record initial state
initial_state = {
    "dof_enabled": camera.data.dof.use_dof,
    "fstop": camera.data.dof.aperture_fstop,
    "focus_distance": camera.data.dof.focus_distance,
    "frame_start": scene.frame_start,
    "frame_end": scene.frame_end
}
with open("/tmp/initial_state.json", "w") as f:
    json.dump(initial_state, f)
PYEOF

# Run Blender headlessly to create the scene
echo "Creating procedural scene..."
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_rack_focus_scene.py" > /dev/null 2>&1

# Start Blender with the created scene
echo "Launching Blender..."
pkill -f blender 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/rack_focus_scene.blend &"

# Wait for Blender
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true
sleep 1

# Dismiss splash/popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="