#!/bin/bash
echo "=== Setting up PBR Material Assembly Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# ================================================================
# PREPARE ASSETS (Real Texture Data)
# ================================================================
ASSET_DIR="/home/ga/Assets/Textures"
mkdir -p "$ASSET_DIR"
chown ga:ga "$ASSET_DIR"

echo "Downloading PBR textures..."

# URLs for a CC0 sand/beach texture (PolyHaven or similar)
# Using robust fallbacks if specific URLs fail
URL_BASE="https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/aerial_beach_01"
FILES=(
    "aerial_beach_01_diff_1k.jpg:diffuse.jpg"
    "aerial_beach_01_rough_1k.jpg:roughness.jpg"
    "aerial_beach_01_nor_gl_1k.jpg:normal.jpg"
)

cd "$ASSET_DIR" || exit 1

for file_pair in "${FILES[@]}"; do
    url_file="${file_pair%%:*}"
    local_name="${file_pair##*:}"
    
    if [ ! -f "$local_name" ]; then
        echo "Downloading $local_name..."
        wget -q "$URL_BASE/$url_file" -O "$local_name" || {
            echo "Primary download failed for $local_name. creating fallback placeholder (NOT IDEAL)."
            # Create a noise texture with ImageMagick if download fails (fallback only)
            convert -size 1024x1024 xc:gray +noise Random "$local_name"
        }
    fi
    chmod 644 "$local_name"
    chown ga:ga "$local_name"
done

echo "Textures prepared in $ASSET_DIR"
ls -l "$ASSET_DIR"

# ================================================================
# CREATE STARTING BLEND FILE
# ================================================================
PROJECT_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"
START_FILE="$PROJECT_DIR/material_setup.blend"

echo "Creating initial Blender scene..."

# Python script to generate the scene
cat > /tmp/create_scene.py << 'PYEOF'
import bpy
import os

# Clear existing
bpy.ops.wm.read_homefile(use_empty=True)

# Create Ground Plane
bpy.ops.mesh.primitive_plane_add(size=4, location=(0, 0, 0))
plane = bpy.context.active_object
plane.name = "GroundPlane"

# Create new material
mat = bpy.data.materials.new(name="SandMaterial")
mat.use_nodes = True
plane.data.materials.append(mat)

# Clean up default nodes (leave only Output and Principled BSDF)
nodes = mat.node_tree.nodes
for node in nodes:
    nodes.remove(node)

# Add Output and BSDF fresh
out_node = nodes.new(type='ShaderNodeOutputMaterial')
out_node.location = (300, 0)
bsdf_node = nodes.new(type='ShaderNodeBsdfPrincipled')
bsdf_node.location = (0, 0)
mat.node_tree.links.new(bsdf_node.outputs['BSDF'], out_node.inputs['Surface'])

# Add Camera
bpy.ops.object.camera_add(location=(0, -3, 2.5), rotation=(0.9, 0, 0))
cam = bpy.context.active_object
cam.name = "Camera"
bpy.context.scene.camera = cam

# Add Light (Sun)
bpy.ops.object.light_add(type='SUN', location=(5, -5, 10))
sun = bpy.context.active_object
sun.data.energy = 3.0
sun.rotation_euler = (0.5, 0.2, 0.5)

# Set Render Settings (Cycles for PBR accuracy, but Eevee is fine for checking)
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 32
bpy.context.scene.render.resolution_x = 1024
bpy.context.scene.render.resolution_y = 1024

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/material_setup.blend")
PYEOF

# Run generation script
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_scene.py"

# Clean up
rm -f /tmp/create_scene.py

# ================================================================
# LAUNCH BLENDER
# ================================================================
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$START_FILE' &"

# Record start time
date +%s > /tmp/task_start_time

# Wait for Blender
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        echo "Blender started."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Switch to Shading workspace (optional, but helpful context)
# We can't easily force workspace via CLI args without a script, but the default layout is fine.

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="