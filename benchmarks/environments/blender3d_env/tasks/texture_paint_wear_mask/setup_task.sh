#!/bin/bash
echo "=== Setting up texture_paint_wear_mask task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Directories
PROJECT_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# Clean up previous runs
rm -f "$PROJECT_DIR/wear_mask.png"
rm -f "$PROJECT_DIR/distressed_crate.blend"

# ================================================================
# CREATE STARTING SCENE (Crate with NO UVs)
# ================================================================
START_BLEND="$PROJECT_DIR/crate_model.blend"

echo "Creating starting scene..."
cat > /tmp/create_crate.py << 'PYEOF'
import bpy
import bmesh

# Clear scene
bpy.ops.wm.read_homefile(use_empty=True)

# Create Cube (The Crate)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
crate = bpy.context.active_object
crate.name = "SciFiCrate"

# Add Bevel Modifier for look
mod = crate.modifiers.new(name="Bevel", type='BEVEL')
mod.width = 0.05
mod.segments = 3

# Clear UVs (User must unwrap)
if crate.data.uv_layers:
    while crate.data.uv_layers:
        crate.data.uv_layers.remove(crate.data.uv_layers[0])

# Add Default Material
mat = bpy.data.materials.new(name="CrateMaterial")
mat.use_nodes = True
crate.data.materials.append(mat)
bsdf = mat.node_tree.nodes.get("Principled BSDF")
if bsdf:
    bsdf.inputs["Base Color"].default_value = (0.05, 0.2, 0.5, 1.0) # Blueish

# Add Lights
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
bpy.context.object.data.energy = 3.0

bpy.ops.object.light_add(type='POINT', location=(-3, -3, 5))
bpy.context.object.data.energy = 100.0

# Add Camera
bpy.ops.object.camera_add(location=(4, -4, 3))
cam = bpy.context.active_object
cam.rotation_euler = (1.1, 0, 0.785)
bpy.context.scene.camera = cam

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/crate_model.blend")
PYEOF

# Run creation script
su - ga -c "/opt/blender/blender --background --python /tmp/create_crate.py"

# ================================================================
# LAUNCH BLENDER
# ================================================================
echo "Launching Blender with crate_model.blend..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$START_BLEND' &"

# Wait for Blender
sleep 5
focus_blender
sleep 1
maximize_blender

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="