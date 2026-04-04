#!/bin/bash
set -e
echo "=== Setting up text_signage_metallic task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and has permissions
mkdir -p /home/ga/BlenderProjects
chown -R ga:ga /home/ga/BlenderProjects

# Clean up previous run artifacts
rm -f /home/ga/BlenderProjects/sign_render.png
rm -f /home/ga/BlenderProjects/sign_scene.blend
rm -f /tmp/task_result.json

# Define baseline scene path
BASELINE="/home/ga/BlenderProjects/baseline_scene.blend"

# Create baseline scene if it doesn't exist (failsafe)
if [ ! -f "$BASELINE" ]; then
    echo "Creating baseline scene..."
    cat > /tmp/create_baseline.py << 'PYEOF'
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
# Cube
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
cube = bpy.context.active_object
cube.name = "BaseCube"
mat = bpy.data.materials.new(name="CubeMaterial")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.8, 0.2, 0.2, 1.0)
cube.data.materials.append(mat)
# Camera
bpy.ops.object.camera_add(location=(7, -6, 5))
cam = bpy.context.active_object
cam.name = "MainCamera"
constraint = cam.constraints.new(type='TRACK_TO')
constraint.target = cube
constraint.track_axis = 'TRACK_NEGATIVE_Z'
constraint.up_axis = 'UP_Y'
bpy.context.scene.camera = cam
# Light
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
sun = bpy.context.active_object
sun.name = "SunLight"
sun.data.energy = 3.0
# Ground
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
# Render settings
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 32
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")
PYEOF
    su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_baseline.py"
fi

# Kill any existing Blender instances
pkill -f blender 2>/dev/null || true
sleep 2

# Launch Blender with baseline scene
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$BASELINE' &"
sleep 10

# Maximize and focus
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Dismiss splash screen if present
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="