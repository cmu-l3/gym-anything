#!/bin/bash
echo "=== Setting up VFX Matchmove Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
FOOTAGE_DIR="/home/ga/footage"
mkdir -p "$FOOTAGE_DIR"
chown ga:ga "$FOOTAGE_DIR"

PROJECT_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# Clean previous output
rm -f "$PROJECT_DIR/tracking_solved.blend"

echo "Generating synthetic tracking footage..."

# Create a Python script to generate high-contrast tracking footage
# We use the Workbench engine for instant rendering of black/white markers
GEN_SCRIPT=$(mktemp /tmp/gen_footage.XXXXXX.py)
cat > "$GEN_SCRIPT" << 'PYEOF'
import bpy
import random
import math

# Setup Scene
bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.frame_start = 1
scene.frame_end = 40
scene.display_settings.display_device = 'sRGB'
scene.view_settings.view_transform = 'Standard'

# Workbench settings for flat, high contrast look
scene.display.shading.light = 'FLAT'
scene.display.shading.color_type = 'OBJECT'
scene.display.render_aa = 'FXAA'

# Create Ground Plane (White)
bpy.ops.mesh.primitive_plane_add(size=100, location=(0, 0, 0))
ground = bpy.context.active_object
ground.color = (0.9, 0.9, 0.9, 1.0)  # White

# Scatter Tracking Markers (Black Cubes/Cones)
# Using varied geometry helps feature detection
for i in range(60):
    x = random.uniform(-15, 15)
    y = random.uniform(-15, 15)
    z = 0.5 if random.random() > 0.5 else 1.0
    
    if random.random() > 0.5:
        bpy.ops.mesh.primitive_cube_add(size=random.uniform(0.5, 1.5), location=(x, y, z/2))
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=random.uniform(0.3, 0.8), depth=z, location=(x, y, z/2))
        
    obj = bpy.context.active_object
    obj.color = (0.05, 0.05, 0.05, 1.0)  # Dark Grey/Black

# Setup Camera Animation (Trucking shot + slight rotation)
bpy.ops.object.camera_add(location=(15, -15, 8), rotation=(math.radians(60), 0, math.radians(45)))
cam = bpy.context.active_object
scene.camera = cam

# Keyframe 1
cam.location = (12, -12, 7)
cam.rotation_euler = (math.radians(55), 0, math.radians(45))
cam.keyframe_insert(data_path="location", frame=1)
cam.keyframe_insert(data_path="rotation_euler", frame=1)

# Keyframe 40
cam.location = (-5, 5, 5)
cam.rotation_euler = (math.radians(50), 0, math.radians(60))
cam.keyframe_insert(data_path="location", frame=40)
cam.keyframe_insert(data_path="rotation_euler", frame=40)

# Render Output
scene.render.filepath = "/home/ga/footage/frame_"
bpy.ops.render.render(animation=True)
PYEOF

# Run generation (headless)
su - ga -c "/opt/blender/blender --background --python $GEN_SCRIPT" > /tmp/footage_gen.log 2>&1

rm -f "$GEN_SCRIPT"

# Verify footage was created
FRAME_COUNT=$(ls -1 "$FOOTAGE_DIR"/*.png 2>/dev/null | wc -l)
echo "Generated $FRAME_COUNT frames in $FOOTAGE_DIR"

if [ "$FRAME_COUNT" -lt 40 ]; then
    echo "ERROR: Footage generation failed. Check /tmp/footage_gen.log"
    exit 1
fi

# Launch Blender fresh for the agent
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender &"

# Wait for window
wait_for_blender 30
maximize_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="