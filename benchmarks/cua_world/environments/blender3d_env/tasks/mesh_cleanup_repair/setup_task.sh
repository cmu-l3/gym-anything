#!/bin/bash
set -e
echo "=== Setting up mesh_cleanup_repair task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Paths
DEMO_DIR="/home/ga/BlenderDemos"
PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR" "$DEMO_DIR"
chown -R ga:ga "$PROJECTS_DIR" "$DEMO_DIR"

BMW_SOURCE="$DEMO_DIR/BMW27.blend"
CORRUPTED_SCENE="$PROJECTS_DIR/bmw_corrupted.blend"
OUTPUT_SCENE="$PROJECTS_DIR/bmw_cleaned.blend"

# Ensure BMW scene exists (download if missing)
if [ ! -f "$BMW_SOURCE" ]; then
    echo "Downloading BMW benchmark scene..."
    wget -q "https://download.blender.org/demo/test/BMW27.blend.zip" -O "$DEMO_DIR/BMW27.zip"
    unzip -q -o "$DEMO_DIR/BMW27.zip" -d "$DEMO_DIR"
    # Handle potential unzip structure
    if [ -f "$DEMO_DIR/BMW27.blend" ]; then
        :
    elif [ -f "$DEMO_DIR/BMW27/BMW27.blend" ]; then
        mv "$DEMO_DIR/BMW27/BMW27.blend" "$BMW_SOURCE"
    fi
    rm -f "$DEMO_DIR/BMW27.zip"
fi

if [ ! -f "$BMW_SOURCE" ]; then
    echo "ERROR: Could not setup source file."
    exit 1
fi

# Remove previous output
rm -f "$OUTPUT_SCENE"

# ================================================================
# CREATE CORRUPTION SCRIPT
# This script runs in Blender to programmatically break the mesh
# ================================================================
cat > /tmp/corrupt_mesh.py << 'PYEOF'
import bpy
import bmesh
import random
import json
import os

# Open source file
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderDemos/BMW27.blend")

# Find the car body mesh (usually largest vertex count)
target_obj = None
max_verts = 0

for obj in bpy.data.objects:
    if obj.type == 'MESH':
        if len(obj.data.vertices) > max_verts:
            max_verts = len(obj.data.vertices)
            target_obj = obj

if not target_obj:
    print("ERROR: No mesh found")
    import sys; sys.exit(1)

# Clean up scene: remove everything else except camera/light
target_obj.name = "BMW_Body_Corrupted"
for obj in list(bpy.data.objects):
    if obj != target_obj and obj.type not in ['CAMERA', 'LIGHT']:
        bpy.data.objects.remove(obj, do_unlink=True)

# Add camera/light if missing
if not any(o.type == 'CAMERA' for o in bpy.data.objects):
    bpy.ops.object.camera_add(location=(8, -6, 5))
    cam = bpy.context.active_object
    cam.rotation_euler = (1.1, 0, 0.9) # Rough lookat
    bpy.context.scene.camera = cam

if not any(o.type == 'LIGHT' for o in bpy.data.objects):
    bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))

# Record original stats
original_stats = {
    "vertex_count": len(target_obj.data.vertices),
    "face_count": len(target_obj.data.polygons)
}

# Apply corruption
bpy.context.view_layer.objects.active = target_obj
bpy.ops.object.mode_set(mode='EDIT')
bm = bmesh.from_edit_mesh(target_obj.data)
bm.verts.ensure_lookup_table()
bm.faces.ensure_lookup_table()

random.seed(42)

# 1. Duplicate Vertices (~150 pairs)
# We duplicate random vertices in place
verts = list(bm.verts)
to_dup = random.sample(verts, min(150, len(verts)))
bmesh.ops.duplicate(bm, geom=to_dup) # Duplicates in place

# 2. Loose Vertices (~80 floating points)
for i in range(80):
    x = random.uniform(-4, 4)
    y = random.uniform(-4, 4)
    z = random.uniform(0, 3)
    bm.verts.new((x, y, z))

# 3. Flip Normals (~30% of faces)
bm.faces.ensure_lookup_table()
faces = list(bm.faces)
to_flip = random.sample(faces, int(len(faces) * 0.3))
for f in to_flip:
    f.normal_flip()

# 4. Degenerate Faces (Zero Area)
# Create a few tiny triangles
for i in range(20):
    v1 = bm.verts.new((0,0,0))
    v2 = bm.verts.new((0.000001,0,0))
    v3 = bm.verts.new((0,0.000001,0))
    try:
        bm.faces.new((v1, v2, v3))
    except:
        pass

bmesh.update_edit_mesh(target_obj.data)
bpy.ops.object.mode_set(mode='OBJECT')

# Save corrupted stats
corrupted_stats = {
    "vertex_count": len(target_obj.data.vertices),
    "face_count": len(target_obj.data.polygons)
}

# Save stats to file for verifier
with open("/tmp/initial_mesh_stats.json", "w") as f:
    json.dump({
        "original": original_stats,
        "corrupted": corrupted_stats
    }, f)

# Save file
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/bmw_corrupted.blend")
print("Corruption complete.")
PYEOF

# Run corruption
echo "Generating corrupted mesh..."
su - ga -c "/opt/blender/blender --background --python /tmp/corrupt_mesh.py" > /dev/null

# Clean up any existing instances
pkill -f blender 2>/dev/null || true

# Launch Blender with corrupted file
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$CORRUPTED_SCENE' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="