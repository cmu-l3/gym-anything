#!/bin/bash
set -e
echo "=== Setting up particle_fur_system_setup task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure baseline scene exists
# The environment setup creates this, but we verify here
BLEND_FILE="/home/ga/BlenderProjects/baseline_scene.blend"
if [ ! -f "$BLEND_FILE" ]; then
    echo "Creating baseline scene..."
    # Fallback creation if env didn't create it
    cat > /tmp/create_baseline.py << 'PYEOF'
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
cube = bpy.context.active_object
cube.name = "BaseCube"
mat = bpy.data.materials.new(name="CubeMaterial")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.8, 0.2, 0.2, 1)
cube.data.materials.append(mat)
bpy.ops.object.camera_add(location=(7, -6, 5))
cam = bpy.context.active_object
cam.name = "MainCamera"
bpy.ops.object.constraint_add(type='TRACK_TO')
cam.constraints['Track To'].target = cube
cam.constraints['Track To'].track_axis = 'TRACK_NEGATIVE_Z'
cam.constraints['Track To'].up_axis = 'UP_Y'
bpy.context.scene.camera = cam
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
bpy.context.active_object.name = "SunLight"
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
bpy.context.active_object.name = "Ground"
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 32
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")
PYEOF
    su - ga -c "/opt/blender/blender --background --python /tmp/create_baseline.py"
fi

# Remove any previous output files
rm -f /home/ga/BlenderProjects/fur_setup.blend
rm -f /home/ga/BlenderProjects/fur_render.png

# Kill any existing Blender instances
pkill -f blender 2>/dev/null || true
sleep 2

# Launch Blender with the baseline scene
echo "Launching Blender with baseline_scene.blend..."
su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/baseline_scene.blend &"
sleep 8

# Wait for Blender window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
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

# Dismiss any splash screen
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="