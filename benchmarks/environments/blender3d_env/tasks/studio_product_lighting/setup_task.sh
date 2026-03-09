#!/bin/bash
echo "=== Setting up studio_product_lighting task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# ================================================================
# CONFIGURATION
# ================================================================
SOURCE_BLEND="/home/ga/BlenderDemos/BMW27.blend"
STRIPPED_BLEND="/home/ga/BlenderProjects/studio_raw.blend"
EXPECTED_BLEND="/home/ga/BlenderProjects/studio_setup.blend"
EXPECTED_RENDER="/home/ga/BlenderProjects/product_shot.png"
PROJECTS_DIR="/home/ga/BlenderProjects"

# Record task start time
date +%s > /tmp/task_start_time

# Ensure projects directory exists
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Remove any existing output files to ensure clean state
rm -f "$EXPECTED_BLEND" 2>/dev/null || true
rm -f "$EXPECTED_RENDER" 2>/dev/null || true
rm -f "$STRIPPED_BLEND" 2>/dev/null || true

# ================================================================
# STRIP LIGHTS AND SET GREY WORLD USING BLENDER PYTHON (HEADLESS)
# ================================================================
echo "Stripping lights from BMW scene and setting grey world..."

STRIP_SCRIPT=$(mktemp /tmp/strip_lights.XXXXXX.py)
cat > "$STRIP_SCRIPT" << 'PYEOF'
import bpy
import json

# Open the source BMW scene
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderDemos/BMW27.blend")

# Record what we are about to remove
removed_lights = []
for obj in list(bpy.data.objects):
    if obj.type == 'LIGHT':
        removed_lights.append({
            "name": obj.name,
            "light_type": obj.data.type if obj.data else "UNKNOWN",
            "location": list(obj.location)
        })
        bpy.data.objects.remove(obj, do_unlink=True)

# Set world background to default grey (0.5, 0.5, 0.5)
world = bpy.context.scene.world
if world is None:
    world = bpy.data.worlds.new("World")
    bpy.context.scene.world = world

if not world.use_nodes:
    world.use_nodes = True

# Find the Background node and set its color to grey
bg_node = None
for node in world.node_tree.nodes:
    if node.type == 'BACKGROUND':
        bg_node = node
        break

if bg_node is None:
    bg_node = world.node_tree.nodes.new('ShaderNodeBackground')

# Set to a neutral grey -- NOT studio-appropriate, agent must change this
bg_node.inputs['Color'].default_value = (0.5, 0.5, 0.5, 1.0)
bg_node.inputs['Strength'].default_value = 1.0

# Record initial scene state
objects_list = []
for obj in bpy.data.objects:
    objects_list.append({
        "name": obj.name,
        "type": obj.type,
        "location": [round(v, 3) for v in obj.location]
    })

cameras = [o for o in bpy.data.objects if o.type == 'CAMERA']
camera_info = {}
if cameras:
    cam = cameras[0]
    camera_info = {
        "name": cam.name,
        "location": [round(v, 3) for v in cam.location],
        "rotation": [round(v, 3) for v in cam.rotation_euler]
    }

initial_state = {
    "light_count": 0,
    "removed_lights": removed_lights,
    "object_count": len(bpy.data.objects),
    "objects": objects_list,
    "camera": camera_info,
    "world_color": [0.5, 0.5, 0.5],
    "world_strength": 1.0
}

# Save the stripped scene
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/studio_raw.blend")

# Output the initial state as JSON
print("INITIAL_STATE_JSON:" + json.dumps(initial_state))
PYEOF

# Run the strip script headlessly
STRIP_OUTPUT=$(/opt/blender/blender --background --python "$STRIP_SCRIPT" 2>/dev/null)
INITIAL_STATE_LINE=$(echo "$STRIP_OUTPUT" | grep '^INITIAL_STATE_JSON:' | head -1)

if [ -n "$INITIAL_STATE_LINE" ]; then
    INITIAL_STATE="${INITIAL_STATE_LINE#INITIAL_STATE_JSON:}"
else
    echo "WARNING: Could not extract initial state from Blender output"
    INITIAL_STATE='{"light_count": 0, "object_count": 0, "objects": [], "removed_lights": [], "camera": {}, "world_color": [0.5, 0.5, 0.5], "world_strength": 1.0}'
fi

rm -f "$STRIP_SCRIPT"

# ================================================================
# SAVE INITIAL STATE
# ================================================================
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)",
    "source_blend": "$SOURCE_BLEND",
    "stripped_blend": "$STRIPPED_BLEND",
    "expected_blend": "$EXPECTED_BLEND",
    "expected_render": "$EXPECTED_RENDER",
    "initial_scene": $INITIAL_STATE,
    "blend_output_exists": false,
    "render_output_exists": false
}
EOF

chmod 666 /tmp/initial_state.json 2>/dev/null || true

echo "Initial state recorded:"
cat /tmp/initial_state.json

# ================================================================
# KILL EXISTING BLENDER AND LAUNCH WITH STRIPPED SCENE
# ================================================================
echo "Stopping any existing Blender instances..."
pkill -9 -x blender 2>/dev/null || true
sleep 2

echo "Launching Blender with stripped scene (no lights)..."
if [ -f "$STRIPPED_BLEND" ]; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$STRIPPED_BLEND' &"
else
    echo "WARNING: Stripped blend file not created, using source..."
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$SOURCE_BLEND' &"
fi
sleep 5

# Focus and maximize Blender window
focus_blender 2>/dev/null || true
sleep 1
maximize_blender 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Scene: BMW car model loaded with ALL lights removed"
echo "World background: grey (0.5, 0.5, 0.5) -- needs to be set to dark"
echo "Expected blend output: $EXPECTED_BLEND"
echo "Expected render output: $EXPECTED_RENDER"
