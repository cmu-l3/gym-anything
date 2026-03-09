#!/bin/bash
echo "=== Setting up copper_pipe_curve_modeling task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
BASELINE_BLEND="/home/ga/BlenderProjects/baseline_scene.blend"
OUTPUT_BLEND="/home/ga/BlenderProjects/pipe_system.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/pipe_render.png"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any existing output files to ensure clean state
rm -f "$OUTPUT_BLEND" 2>/dev/null || true
rm -f "$OUTPUT_RENDER" 2>/dev/null || true

# Record initial state (should be 0 curves)
cat > /tmp/initial_state.json << EOF
{
    "curve_count": 0,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure baseline scene exists (created by environment setup)
if [ ! -f "$BASELINE_BLEND" ]; then
    echo "Creating simple baseline scene..."
    cat > /tmp/create_baseline.py << 'PYEOF'
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
bpy.context.active_object.name = "BaseCube"
bpy.ops.object.camera_add(location=(7, -6, 5))
cam = bpy.context.active_object
cam.name = "MainCamera"
bpy.ops.object.constraint_add(type='TRACK_TO')
cam.constraints['Track To'].target = bpy.data.objects['BaseCube']
cam.constraints['Track To'].track_axis = 'TRACK_NEGATIVE_Z'
cam.constraints['Track To'].up_axis = 'UP_Y'
bpy.context.scene.camera = cam
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
bpy.ops.mesh.primitive_plane_add(size=20)
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 32
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")
PYEOF
    /opt/blender/blender --background --python /tmp/create_baseline.py > /dev/null 2>&1
fi

# Ensure Blender is running with baseline scene
echo "Checking Blender status..."
if ! pgrep -f "blender" > /dev/null; then
    echo "Starting Blender..."
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$BASELINE_BLEND' &"
    sleep 8
else
    # If running, we assume it's in a usable state, but ideally we'd reload
    echo "Blender already running"
fi

# Focus and maximize
focus_blender
sleep 1
maximize_blender
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="