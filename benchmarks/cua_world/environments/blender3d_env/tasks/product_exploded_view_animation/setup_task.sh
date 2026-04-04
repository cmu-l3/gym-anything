#!/bin/bash
echo "=== Setting up product_exploded_view_animation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

SOURCE_BLEND="$PROJECTS_DIR/device_stack.blend"
EXPECTED_BLEND="$PROJECTS_DIR/exploded_view.blend"
EXPECTED_RENDER="$PROJECTS_DIR/exploded_view.png"

# Remove previous outputs
rm -f "$EXPECTED_BLEND" "$EXPECTED_RENDER" 2>/dev/null

# Record start time
date +%s > /tmp/task_start_time

# ================================================================
# GENERATE STARTING SCENE
# ================================================================
echo "Generating starting scene with stacked objects..."
GEN_SCRIPT=$(mktemp /tmp/gen_scene.XXXXXX.py)

cat > "$GEN_SCRIPT" << 'PYEOF'
import bpy
import random

# Clear existing objects
bpy.ops.wm.read_homefile(use_empty=True)

# Helper to create material
def create_mat(name, color):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    return mat

mat_red = create_mat("RedMat", (0.8, 0.1, 0.1, 1.0))
mat_green = create_mat("GreenMat", (0.1, 0.8, 0.1, 1.0))
mat_blue = create_mat("BlueMat", (0.1, 0.1, 0.8, 1.0))
mat_grey = create_mat("GreyMat", (0.2, 0.2, 0.2, 1.0))

# Create Case Bottom
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
obj = bpy.context.active_object
obj.name = "Case_Bottom"
obj.scale = (2.0, 1.5, 0.2)
obj.data.materials.append(mat_grey)

# Create Battery
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.25))
obj = bpy.context.active_object
obj.name = "Battery"
obj.scale = (1.0, 0.8, 0.15)
obj.data.materials.append(mat_blue)

# Create Circuit Board
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.45))
obj = bpy.context.active_object
obj.name = "Circuit_Board"
obj.scale = (1.8, 1.3, 0.05)
obj.data.materials.append(mat_green)

# Create Case Top
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.6))
obj = bpy.context.active_object
obj.name = "Case_Top"
obj.scale = (2.0, 1.5, 0.2)
obj.data.materials.append(mat_red)

# Setup Camera
bpy.ops.object.camera_add(location=(5, -5, 4))
cam = bpy.context.active_object
cam.name = "Camera"
cam.rotation_euler = (1.0, 0, 0.785)
bpy.context.scene.camera = cam

# Setup Light
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
light = bpy.context.active_object
light.data.energy = 3.0

# Set Frame Range Default
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 250

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/device_stack.blend")
print("Scene generated successfully.")
PYEOF

# Run generation
/opt/blender/blender --background --python "$GEN_SCRIPT" > /tmp/scene_gen.log 2>&1
rm -f "$GEN_SCRIPT"

# Ensure permissions
chown ga:ga "$SOURCE_BLEND"

# ================================================================
# RECORD INITIAL STATE
# ================================================================
# Just simple file stats for initial state
INITIAL_SIZE=$(stat -c%s "$SOURCE_BLEND" 2>/dev/null || echo "0")
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "initial_blend_size": $INITIAL_SIZE
}
EOF

# ================================================================
# LAUNCH BLENDER
# ================================================================
# Stop existing
pkill -9 -x blender 2>/dev/null || true
sleep 1

# Start Blender
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$SOURCE_BLEND' &"
sleep 5

# Setup Window
focus_blender
sleep 1
maximize_blender

# Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="