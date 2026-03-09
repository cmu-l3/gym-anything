#!/bin/bash
echo "=== Setting up VFX Shadow Catcher Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Configuration
DEMO_BLEND="/home/ga/BlenderDemos/BMW27.blend"
START_BLEND="/home/ga/BlenderProjects/vfx_start.blend"
PROJECTS_DIR="/home/ga/BlenderProjects"

mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Clean previous outputs
rm -f "/home/ga/BlenderProjects/shadow_setup.blend" 2>/dev/null || true
rm -f "/home/ga/BlenderProjects/shadow_composite.png" 2>/dev/null || true

# ==============================================================================
# CREATE STARTING SCENE
# Use the BMW demo, add a standard ground plane, disable transparency settings
# ==============================================================================
echo "Creating starting scene from $DEMO_BLEND..."

CREATE_SCENE_SCRIPT=$(mktemp /tmp/create_scene.XXXXXX.py)
cat > "$CREATE_SCENE_SCRIPT" << 'PYEOF'
import bpy

# Open BMW demo
try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderDemos/BMW27.blend")
except:
    # Fallback if BMW not found, create simple scene
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.mesh.primitive_cube_add(location=(0,0,1))
    bpy.context.object.name = "Car_Proxy"

# 1. Setup Ground Plane
# Remove existing floor if it exists to ensure we have a clean "GroundPlane"
for obj in bpy.data.objects:
    if "floor" in obj.name.lower() or "ground" in obj.name.lower() or "plane" in obj.name.lower():
        bpy.data.objects.remove(obj, do_unlink=True)

# Add new GroundPlane
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "GroundPlane"

# Give it a simple white material
mat = bpy.data.materials.new(name="GroundMat")
mat.use_nodes = True
ground.data.materials.append(mat)

# 2. Reset Render Settings (The "Problem" State)
scene = bpy.context.scene

# Set to Cycles (usually needed for Shadow Catcher, but let's ensure it starts there or Eevee)
# We'll start in Cycles but with wrong settings
scene.render.engine = 'CYCLES'

# Disable Film Transparency (Critical for task)
scene.render.film_transparent = False

# Ensure Shadow Catcher is OFF (Critical for task)
ground.is_shadow_catcher = False

# Set specific resolution for faster rendering during test
scene.render.resolution_x = 960
scene.render.resolution_y = 540
scene.render.resolution_percentage = 100
scene.cycles.samples = 16  # Low samples for speed

# 3. Setup World/Background
# Make sure there is a visible background so transparency is obvious when it fails
world = scene.world
if not world:
    world = bpy.data.worlds.new("World")
    scene.world = world
world.use_nodes = True
bg_node = world.node_tree.nodes.get('Background')
if not bg_node:
    bg_node = world.node_tree.nodes.new('ShaderNodeBackground')
bg_node.inputs[0].default_value = (0.2, 0.4, 0.8, 1) # Blue sky color
bg_node.inputs[1].default_value = 1.0

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/vfx_start.blend")
print("VFX start scene created successfully")
PYEOF

# Run generation script
/opt/blender/blender --background --python "$CREATE_SCENE_SCRIPT" > /tmp/scene_gen.log 2>&1

# Verify generation
if [ ! -f "$START_BLEND" ]; then
    echo "ERROR: Failed to generate start scene. Log:"
    cat /tmp/scene_gen.log
    exit 1
fi

chown ga:ga "$START_BLEND"
rm -f "$CREATE_SCENE_SCRIPT"

# ==============================================================================
# LAUNCH BLENDER
# ==============================================================================
echo "Launching Blender..."
pkill -x blender 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 /opt/blender/blender '$START_BLEND' &"

# Wait for window
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Capture initial state
take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="