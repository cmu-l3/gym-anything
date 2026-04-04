#!/bin/bash
set -e
echo "=== Setting up texture_bake_game_export task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

PROJECTS_DIR="/home/ga/BlenderProjects"
BLEND_SOURCE="$PROJECTS_DIR/baseline_scene.blend"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean any previous task outputs
rm -f "$PROJECTS_DIR/baked_ao.png"
rm -f "$PROJECTS_DIR/baked_diffuse.png"
rm -f "$PROJECTS_DIR/bake_project.blend"
rm -f /tmp/task_result.json

# Ensure baseline scene exists
if [ ! -f "$BLEND_SOURCE" ]; then
    echo "Baseline scene not found, attempting to recreate..."
    # Fallback if the environment didn't create it
    # We will create it via the python script below anyway
fi

# Modify baseline scene: add Bevel modifier to BaseCube for interesting AO
# and ensure clean state
cat > /tmp/prepare_bake_scene.py << 'PYEOF'
import bpy
import os

# Create/Reset scene
bpy.ops.wm.read_homefile(use_empty=True)

# Create BaseCube with Bevel
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
cube = bpy.context.active_object
cube.name = "BaseCube"

# Add Bevel modifier for geometric detail (creates interesting AO)
bpy.ops.object.modifier_add(type='BEVEL')
bevel = cube.modifiers['Bevel']
bevel.width = 0.15
bevel.segments = 3
bevel.limit_method = 'ANGLE'

# Add Material
mat = bpy.data.materials.new(name="CubeMaterial")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
if bsdf:
    # Set to a distinct Red color: (0.8, 0.2, 0.2, 1.0)
    bsdf.inputs["Base Color"].default_value = (0.8, 0.2, 0.2, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.5
cube.data.materials.append(mat)

# Ensure UV Map exists (Smart UV Project)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=66, island_margin=0.02)
bpy.ops.object.mode_set(mode='OBJECT')

# Add Ground Plane
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"

# Add Camera
bpy.ops.object.camera_add(location=(5, -5, 4))
camera = bpy.context.active_object
camera.name = "MainCamera"
# Point camera at cube
bpy.ops.object.constraint_add(type='TRACK_TO')
camera.constraints['Track To'].target = cube
camera.constraints['Track To'].track_axis = 'TRACK_NEGATIVE_Z'
camera.constraints['Track To'].up_axis = 'UP_Y'
bpy.context.scene.camera = camera

# Add Sun Light
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
sun = bpy.context.active_object
sun.name = "SunLight"
sun.data.energy = 3.0

# Set Render Engine to Cycles (Required for baking)
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 32
bpy.context.scene.cycles.use_denoising = True

# Save prepared file
output_path = "/home/ga/BlenderProjects/baseline_scene.blend"
if not os.path.exists(os.path.dirname(output_path)):
    os.makedirs(os.path.dirname(output_path))
bpy.ops.wm.save_as_mainfile(filepath=output_path)
print(f"Scene prepared and saved to {output_path}")
PYEOF

# Run preparation script
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/prepare_bake_scene.py" 2>&1 | tail -20

# Kill any running Blender instances
pkill -f blender 2>/dev/null || true
sleep 2

# Launch Blender with the prepared scene
echo "Launching Blender with prepared scene..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$PROJECTS_DIR/baseline_scene.blend' &"
sleep 5

# Wait for Blender window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus Blender
# Using wmctrl to maximize ensures the UI is fully visible for the agent
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true
sleep 1

# Dismiss any splash screen
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="