#!/bin/bash
echo "=== Setting up Geometry Nodes Curve Fence task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Directories
PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Record task start time
date +%s > /tmp/task_start_time

# ================================================================
# GENERATE BASELINE BLEND FILE
# ================================================================
# We generate the file programmatically to ensure a clean state
# with specific curve geometry and asset names.

BASELINE_SCRIPT=$(mktemp /tmp/create_baseline.XXXXXX.py)
cat > "$BASELINE_SCRIPT" << 'PYEOF'
import bpy
import math

# Clear default scene
bpy.ops.wm.read_homefile(use_empty=True)

# 1. Create the Fence Post (The asset to instance)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -2, 0.6))
post = bpy.context.active_object
post.name = "FencePost"
# Scale to look like a post (15cm x 15cm x 1.2m)
post.scale = (0.15, 0.15, 1.2)
# Apply scale so instances are correct size
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# Add a simple material
mat = bpy.data.materials.new(name="Wood")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.35, 0.25, 0.15, 1.0)
bsdf.inputs["Roughness"].default_value = 0.8
post.data.materials.append(mat)

# 2. Create the Path (Bezier Curve)
# Create a curve with some curvature to test alignment
bpy.ops.curve.primitive_bezier_curve_add(radius=1, location=(0, 0, 0))
path = bpy.context.active_object
path.name = "FencePath"

# Enter edit mode to shape the curve
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.curve.select_all(action='SELECT')
bpy.ops.curve.delete(type='VERT')

# Draw an S-shape
bpy.ops.curve.vertex_add(location=(0, 0, 0))
bpy.ops.curve.vertex_add(location=(5, 5, 0))
bpy.ops.curve.vertex_add(location=(10, 0, 0))
bpy.ops.curve.vertex_add(location=(15, 5, 0))

# Smooth handles
bpy.ops.curve.select_all(action='SELECT')
bpy.ops.curve.handle_type_set(type='AUTOMATIC')
bpy.ops.object.mode_set(mode='OBJECT')

# 3. Setup Camera and Light
bpy.ops.object.camera_add(location=(8, -12, 10))
cam = bpy.context.active_object
cam.rotation_euler = (math.radians(60), 0, math.radians(15))
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
sun = bpy.context.active_object
sun.data.energy = 3.0

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/fence_baseline.blend")
PYEOF

echo "Generating baseline scene..."
/opt/blender/blender --background --python "$BASELINE_SCRIPT" 2>/dev/null
rm -f "$BASELINE_SCRIPT"

# Set ownership
chown ga:ga "/home/ga/BlenderProjects/fence_baseline.blend"

# ================================================================
# LAUNCH BLENDER
# ================================================================
echo "Launching Blender..."
pkill -9 -x blender 2>/dev/null || true
su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/fence_baseline.blend &"

# Wait for Blender
for i in {1..30}; do
    if wmctrl -l | grep -qi "blender"; then
        break
    fi
    sleep 1
done

# Focus and maximize
focus_blender
sleep 1
maximize_blender
sleep 1

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="