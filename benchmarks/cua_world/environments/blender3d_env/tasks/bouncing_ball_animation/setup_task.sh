#!/bin/bash
echo "=== Setting up bouncing_ball_animation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
SOURCE_BLEND="/home/ga/BlenderProjects/baseline_scene.blend"
OUTPUT_BLEND="/home/ga/BlenderProjects/bouncing_ball.blend"

# Ensure baseline scene exists (created by environment setup, but safe to verify)
if [ ! -f "$SOURCE_BLEND" ]; then
    echo "Creating fallback baseline scene..."
    # Fallback python script to create a simple scene if baseline is missing
    cat > /tmp/create_fallback.py << 'PYEOF'
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
bpy.context.active_object.name = "BaseCube"
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
bpy.context.active_object.name = "Ground"
bpy.ops.object.camera_add(location=(7, -6, 5))
cam = bpy.context.active_object
cam.name = "MainCamera"
bpy.ops.object.constraint_add(type='TRACK_TO')
cam.constraints['Track To'].target = bpy.data.objects['BaseCube']
cam.constraints['Track To'].track_axis = 'TRACK_NEGATIVE_Z'
cam.constraints['Track To'].up_axis = 'UP_Y'
bpy.context.scene.camera = cam
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")
PYEOF
    /opt/blender/blender --background --python /tmp/create_fallback.py >/dev/null 2>&1
fi

# Remove any existing output file to ensure clean state
rm -f "$OUTPUT_BLEND"
echo "Cleaned existing output file: $OUTPUT_BLEND"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time

# ================================================================
# Launch Blender with baseline scene
# ================================================================
echo "Checking Blender status..."
pkill -x blender 2>/dev/null || true
sleep 1

echo "Starting Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$SOURCE_BLEND' &"
sleep 8

# Focus and maximize Blender window
focus_blender
sleep 1
maximize_blender
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Create bouncing ball animation and save to $OUTPUT_BLEND"