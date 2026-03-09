#!/bin/bash
echo "=== Setting up boolean_wall_openings task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Configuration
PROJECTS_DIR="/home/ga/BlenderProjects"
START_BLEND="$PROJECTS_DIR/boolean_task.blend"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Record task start time
date +%s > /tmp/task_start_time

# ================================================================
# GENERATE PROCEDURAL SCENE
# ================================================================
# We create the scene from scratch to ensure a clean state
# Wall: 10m x 0.3m x 4m
# Cutters: Intersecting geometry

GENERATOR_SCRIPT=$(mktemp /tmp/gen_scene.XXXXXX.py)
cat > "$GENERATOR_SCRIPT" << 'PYEOF'
import bpy
import math

# Clear existing objects
bpy.ops.wm.read_homefile(use_empty=True)

# 1. Create Wall
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 2))
wall = bpy.context.active_object
wall.name = "Wall"
wall.scale = (10, 0.3, 4)
# Apply scale so booleans work cleanly
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# Add grey material to wall
mat_wall = bpy.data.materials.new(name="WallMat")
mat_wall.use_nodes = True
bsdf = mat_wall.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.7, 0.7, 0.7, 1.0)
wall.data.materials.append(mat_wall)

# 2. Create Cutter Material (Red)
mat_cutter = bpy.data.materials.new(name="CutterMat")
mat_cutter.use_nodes = True
bsdf = mat_cutter.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.8, 0.1, 0.1, 1.0)

# 3. Create Left Window Cutter
bpy.ops.mesh.primitive_cube_add(size=1, location=(-2.5, 0, 2.5))
cut1 = bpy.context.active_object
cut1.name = "WindowCutter_Left"
cut1.scale = (1.2, 1.0, 1.2) # Thicker than wall to ensure cut
cut1.data.materials.append(mat_cutter)

# 4. Create Right Window Cutter
bpy.ops.mesh.primitive_cube_add(size=1, location=(2.5, 0, 2.5))
cut2 = bpy.context.active_object
cut2.name = "WindowCutter_Right"
cut2.scale = (1.2, 1.0, 1.2)
cut2.data.materials.append(mat_cutter)

# 5. Create Door Cutter
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1.1))
cut3 = bpy.context.active_object
cut3.name = "DoorCutter"
cut3.scale = (1.0, 1.0, 2.2)
cut3.data.materials.append(mat_cutter)

# 6. Setup Camera
bpy.ops.object.camera_add(location=(0, -8, 2), rotation=(math.radians(90), 0, 0))
cam = bpy.context.active_object
cam.name = "MainCamera"
bpy.context.scene.camera = cam

# 7. Setup Lighting
bpy.ops.object.light_add(type='SUN', location=(5, -5, 10))
sun = bpy.context.active_object
sun.name = "SunLight"
sun.data.energy = 5.0
# Point sun at wall
bpy.ops.object.constraint_add(type='TRACK_TO')
sun.constraints["Track To"].target = wall

# 8. Render Settings
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.render.resolution_x = 960
scene.render.resolution_y = 540
scene.render.resolution_percentage = 100

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/boolean_task.blend")

# Output initial state info
print(f"INITIAL_FACE_COUNT:{len(wall.data.polygons)}")
PYEOF

# Run generation script
echo "Generating scene..."
GEN_OUTPUT=$(/opt/blender/blender --background --python "$GENERATOR_SCRIPT" 2>/dev/null)
INITIAL_FACES=$(echo "$GEN_OUTPUT" | grep "INITIAL_FACE_COUNT" | cut -d':' -f2 || echo "6")
rm -f "$GENERATOR_SCRIPT"

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "initial_face_count": $INITIAL_FACES,
    "timestamp": "$(date -Iseconds)"
}
EOF

# ================================================================
# LAUNCH BLENDER
# ================================================================
# Ensure no other Blender instances
pkill -9 -x blender 2>/dev/null || true
sleep 1

echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$START_BLEND' &"

# Wait for Blender window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender" > /dev/null; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done
sleep 5

# Focus and Maximize
focus_blender
sleep 1
maximize_blender
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="