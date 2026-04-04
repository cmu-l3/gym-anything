#!/bin/bash
set -e
echo "=== Setting up radial_array_modifier_setup task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
PROJECTS_DIR="/home/ga/BlenderProjects"
BASELINE_BLEND="$PROJECTS_DIR/baseline_scene.blend"
OUTPUT_BLEND="$PROJECTS_DIR/fan_assembly.blend"

# Ensure projects directory exists
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Clean up previous runs
rm -f "$OUTPUT_BLEND" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure baseline scene exists (create if missing)
if [ ! -f "$BASELINE_BLEND" ]; then
    echo "Creating baseline scene..."
    cat > /tmp/create_baseline.py << 'PYEOF'
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
cube = bpy.context.active_object
cube.name = "BaseCube"
bpy.ops.object.camera_add(location=(7, -6, 5))
cam = bpy.context.active_object
cam.name = "MainCamera"
bpy.ops.object.constraint_add(type='TRACK_TO')
cam.constraints['Track To'].target = cube
cam.constraints['Track To'].track_axis = 'TRACK_NEGATIVE_Z'
cam.constraints['Track To'].up_axis = 'UP_Y'
bpy.context.scene.camera = cam
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
bpy.context.active_object.name = "Ground"
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")
PYEOF
    su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_baseline.py"
fi

# Record initial objects
echo '["BaseCube", "MainCamera", "Sun", "Ground"]' > /tmp/initial_objects.json

# Launch Blender
echo "Launching Blender..."
if ! pgrep -f "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$BASELINE_BLEND' &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="