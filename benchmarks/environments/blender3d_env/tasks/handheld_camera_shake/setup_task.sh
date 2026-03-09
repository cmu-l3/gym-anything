#!/bin/bash
echo "=== Setting up handheld_camera_shake task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Paths
DEMO_BLEND="/home/ga/BlenderDemos/BMW27.blend"
START_BLEND="/home/ga/BlenderProjects/handheld_start.blend"
OUTPUT_BLEND="/home/ga/BlenderProjects/handheld_cam.blend"

# Ensure directories
mkdir -p "/home/ga/BlenderProjects"
chown ga:ga "/home/ga/BlenderProjects"

# Clean previous output
rm -f "$OUTPUT_BLEND" 2>/dev/null

# Prepare the scene:
# 1. Load BMW scene
# 2. Normalize Camera (rename to 'Camera', set to XYZ Euler, clear animation)
# 3. Save as start file
echo "Preparing start scene..."
cat > /tmp/prepare_scene.py << 'PYEOF'
import bpy

# Load demo
try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderDemos/BMW27.blend")
except:
    # Fallback if demo missing
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.object.camera_add(location=(7, -6, 5))

# Setup Camera
cam = bpy.context.scene.camera
if not cam:
    # Find any camera
    cams = [o for o in bpy.data.objects if o.type == 'CAMERA']
    if cams:
        cam = cams[0]
        bpy.context.scene.camera = cam
    else:
        bpy.ops.object.camera_add()
        cam = bpy.context.active_object
        bpy.context.scene.camera = cam

# Normalize
cam.name = "Camera"
cam.rotation_mode = 'XYZ'
cam.animation_data_clear()

# Add a single keyframe at frame 1 so curves exist (making it easier to find in Graph Editor)
# But strictly speaking, the agent might need to insert one. 
# Let's insert a static keyframe to ensure F-Curves exist, helping the agent simply "add modifier"
cam.keyframe_insert(data_path="rotation_euler", frame=1)

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/handheld_start.blend")
PYEOF

/opt/blender/blender --background --python /tmp/prepare_scene.py > /dev/null 2>&1

# Launch Blender with the prepared file
echo "Launching Blender..."
if ! pgrep -x "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$START_BLEND' &"
    sleep 10
fi

# Focus and maximize
focus_blender
sleep 1
maximize_blender
sleep 1

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="