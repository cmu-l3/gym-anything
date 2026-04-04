#!/bin/bash
set -e
echo "=== Setting up Interior Portal Light task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Directories
PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

SCENE_FILE="$PROJECTS_DIR/interior_noise_test.blend"
OUTPUT_FILE="$PROJECTS_DIR/portal_setup.blend"

# Remove output if exists
rm -f "$OUTPUT_FILE"

# Record start time
date +%s > /tmp/task_start_time.txt

# Create the specific interior scene using Blender Python
# We create a simple room with a boolean window cut and a sky texture
echo "Generating interior scene..."
GENERATOR_SCRIPT=$(mktemp /tmp/gen_scene.XXXXXX.py)
cat > "$GENERATOR_SCRIPT" << 'PYEOF'
import bpy
import math

# Clear scene
bpy.ops.wm.read_homefile(use_empty=True)

# 1. Create Room (Cube)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1.5))
room = bpy.context.active_object
room.name = "Room"
room.scale = (4.0, 4.0, 3.0) # 4x4m room, 3m high
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# Invert normals so we see inside (optional, but good for backface culling)
# For Cycles interior, thickness usually matters, but for this test we just need the geometry
bpy.ops.object.modifier_add(type='SOLIDIFY')
room.modifiers["Solidify"].thickness = 0.2
room.modifiers["Solidify"].offset = 1.0 # Outward thickness
bpy.ops.object.modifier_apply(modifier="Solidify")

# 2. Create Window Cutter
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 2.0, 1.5))
cutter = bpy.context.active_object
cutter.name = "WindowCutter"
# Window size: 2m wide (X), 1.5m high (Z), depth passes through wall (Y)
cutter.scale = (2.0, 1.0, 1.5) 
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# 3. Apply Boolean
bpy.context.view_layer.objects.active = room
bpy.ops.object.modifier_add(type='BOOLEAN')
bool_mod = room.modifiers["Boolean"]
bool_mod.operation = 'DIFFERENCE'
bool_mod.object = cutter
bpy.ops.object.modifier_apply(modifier="Boolean")

# Delete cutter
bpy.data.objects.remove(cutter, do_unlink=True)

# 4. Setup World with Sky Texture (Noise source)
world = bpy.context.scene.world
if not world:
    world = bpy.data.worlds.new("World")
    bpy.context.scene.world = world
world.use_nodes = True
nodes = world.node_tree.nodes
links = world.node_tree.links

# Clear default nodes
nodes.clear()

# Add Sky Texture
sky_node = nodes.new(type='ShaderNodeTexSky')
sky_node.location = (-300, 0)
sky_node.sky_type = 'NISHITA'
sky_node.sun_elevation = math.radians(15.0)

# Add Background
bg_node = nodes.new(type='ShaderNodeBackground')
bg_node.location = (0, 0)
bg_node.inputs['Strength'].default_value = 1.0

# Add Output
out_node = nodes.new(type='ShaderNodeOutputWorld')
out_node.location = (300, 0)

# Link
links.new(sky_node.outputs['Color'], bg_node.inputs['Color'])
links.new(bg_node.outputs['Background'], out_node.inputs['Surface'])

# 5. Setup Camera inside room
bpy.ops.object.camera_add(location=(-1.5, -1.5, 1.6))
cam = bpy.context.active_object
cam.rotation_euler = (math.radians(90), 0, math.radians(-45)) # Looking towards the corner/window
bpy.context.scene.camera = cam

# 6. Set Render Engine to Cycles
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.device = 'CPU' # Safe default
bpy.context.scene.cycles.samples = 32

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/interior_noise_test.blend")
PYEOF

# Run generation
/opt/blender/blender --background --python "$GENERATOR_SCRIPT" > /dev/null 2>&1
rm -f "$GENERATOR_SCRIPT"
chown ga:ga "$SCENE_FILE"

# Launch Blender with the scene
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$SCENE_FILE' &"

# Wait for Blender
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        echo "Blender window found."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="