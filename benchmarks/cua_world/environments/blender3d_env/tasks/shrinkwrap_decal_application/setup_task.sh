#!/bin/bash
echo "=== Setting up shrinkwrap_decal_application task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Directories
PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

SOURCE_BLEND="$PROJECTS_DIR/pipe_scene.blend"
OUTPUT_BLEND="$PROJECTS_DIR/pipe_decal.blend"

# Remove previous output
rm -f "$OUTPUT_BLEND" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time

# ================================================================
# GENERATE STARTING SCENE
# ================================================================
echo "Generating pipe scene..."
cat > /tmp/create_pipe_scene.py << 'PYEOF'
import bpy
import math

# Clear scene
bpy.ops.wm.read_homefile(use_empty=True)

# 1. Create the Pipe (Cylinder)
bpy.ops.mesh.primitive_cylinder_add(
    radius=1.0, 
    depth=4.0, 
    location=(0, 0, 0),
    rotation=(math.radians(90), 0, 0)
)
pipe = bpy.context.active_object
pipe.name = "IndustrialPipe"

# Pipe Material (Dark Grey)
mat_pipe = bpy.data.materials.new(name="PipeMat")
mat_pipe.use_nodes = True
bsdf_pipe = mat_pipe.node_tree.nodes["Principled BSDF"]
bsdf_pipe.inputs["Base Color"].default_value = (0.2, 0.2, 0.2, 1.0)
bsdf_pipe.inputs["Roughness"].default_value = 0.4
pipe.data.materials.append(mat_pipe)

# 2. Create the Label (Plane) - Flat and not conforming
# Positioned slightly in front of the pipe
bpy.ops.mesh.primitive_plane_add(
    size=0.6, 
    location=(0, -1.2, 0), 
    rotation=(math.radians(90), 0, 0)
)
label = bpy.context.active_object
label.name = "WarningLabel"

# Label Material (Yellow Warning)
mat_label = bpy.data.materials.new(name="LabelMat")
mat_label.use_nodes = True
bsdf_label = mat_label.node_tree.nodes["Principled BSDF"]
bsdf_label.inputs["Base Color"].default_value = (1.0, 0.8, 0.0, 1.0) # Yellow
label.data.materials.append(mat_label)

# 3. Setup Camera
bpy.ops.object.camera_add(location=(2, -3, 2), rotation=(math.radians(60), 0, math.radians(45)))
cam = bpy.context.active_object
cam.name = "Camera"
bpy.context.scene.camera = cam

# Look at label
bpy.ops.object.constraint_add(type='TRACK_TO')
cam.constraints["Track To"].target = label
cam.constraints["Track To"].track_axis = 'TRACK_NEGATIVE_Z'
cam.constraints["Track To"].up_axis = 'UP_Y'

# 4. Setup Lighting
bpy.ops.object.light_add(type='AREA', location=(2, -4, 4))
light = bpy.context.active_object
light.data.energy = 500
light.data.size = 2

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/pipe_scene.blend")
print("Scene generated successfully.")
PYEOF

# Run generation script
su - ga -c "/opt/blender/blender --background --python /tmp/create_pipe_scene.py"

# ================================================================
# LAUNCH BLENDER
# ================================================================
echo "Launching Blender..."
# Kill any existing instances
pkill -9 -x blender 2>/dev/null || true
sleep 1

# Start Blender with the scene
su - ga -c "DISPLAY=:1 /opt/blender/blender '$SOURCE_BLEND' &"

# Wait for Blender to start
for i in {1..30}; do
    if pgrep -x "blender" > /dev/null; then
        echo "Blender started."
        break
    fi
    sleep 1
done
sleep 5

# Focus and maximize
focus_blender
maximize_blender

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="