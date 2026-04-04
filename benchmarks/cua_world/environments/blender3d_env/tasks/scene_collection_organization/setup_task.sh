#!/bin/bash
set -e
echo "=== Setting up Scene Collection Organization task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECTS_DIR="/home/ga/BlenderProjects"
SCENE_FILE="$PROJECTS_DIR/messy_scene.blend"
OUTPUT_FILE="$PROJECTS_DIR/organized_scene.blend"

mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Remove any previous output to ensure clean state
rm -f "$OUTPUT_FILE"
rm -f /tmp/task_result.json

# Create the messy scene with all objects in one collection via Blender Python
cat > /tmp/create_messy_scene.py << 'SCENE_EOF'
import bpy
import math

# Start fresh
bpy.ops.wm.read_homefile(use_empty=True)

# Ensure one default collection
if not bpy.context.scene.collection.children:
    default_col = bpy.data.collections.new("Collection")
    bpy.context.scene.collection.children.link(default_col)
    collection = default_col
else:
    collection = bpy.context.scene.collection.children[0]

def add_to_collection(obj):
    # Link to default collection, unlink from others if necessary
    if obj.name not in collection.objects:
        collection.objects.link(obj)
    # Ensure it's not in the scene master collection directly if we want it in "Collection"
    if obj.name in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.unlink(obj)

# ============ MESHES (7) ============
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
bpy.context.active_object.name = "BaseCube"

bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=(3, 0, 1))
bpy.context.active_object.name = "Sphere"

bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=3, location=(-3, 2, 1.5))
bpy.context.active_object.name = "Cylinder"

bpy.ops.mesh.primitive_cone_add(radius1=1, depth=2, location=(0, 4, 1))
bpy.context.active_object.name = "Cone"

bpy.ops.mesh.primitive_torus_add(location=(3, 4, 1))
bpy.context.active_object.name = "Torus"

bpy.ops.mesh.primitive_monkey_add(size=1.5, location=(-3, -3, 1.5))
bpy.context.active_object.name = "Suzanne"

bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
bpy.context.active_object.name = "GroundPlane"

# ============ LIGHTS (3) ============
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
bpy.context.active_object.name = "SunLight"

bpy.ops.object.light_add(type='POINT', location=(-2, -2, 4))
bpy.context.active_object.name = "PointLight"

bpy.ops.object.light_add(type='SPOT', location=(0, -5, 6))
bpy.context.active_object.name = "SpotLight"

# ============ CAMERAS (2) ============
bpy.ops.object.camera_add(location=(7, -6, 5))
cam = bpy.context.active_object
cam.name = "MainCamera"
cam.rotation_euler = (1.1, 0.0, 0.8)
bpy.context.scene.camera = cam

bpy.ops.object.camera_add(location=(0, 0, 12))
bpy.context.active_object.name = "OverheadCamera"

# ============ EMPTIES (2) ============
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
bpy.context.active_object.name = "PivotEmpty"

bpy.ops.object.empty_add(type='CUBE', location=(0, 2, 2))
bpy.context.active_object.name = "TargetEmpty"

# Move everything to the single "Collection"
for obj in bpy.data.objects:
    # Unlink from all collections
    for col in obj.users_collection:
        col.objects.unlink(obj)
    # Link to target
    collection.objects.link(obj)

# Save the file
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/messy_scene.blend")
print("Messy scene saved.")
SCENE_EOF

# Generate the scene file
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_messy_scene.py" > /dev/null 2>&1

# Kill any existing Blender instances
pkill -f blender 2>/dev/null || true
sleep 1

# Launch Blender with the messy scene
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$SCENE_FILE' &"

# Wait for Blender window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Dismiss splash screen if present
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="