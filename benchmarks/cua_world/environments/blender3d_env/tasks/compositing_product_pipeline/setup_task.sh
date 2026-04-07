#!/bin/bash
echo "=== Setting up compositing_product_pipeline task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# ================================================================
# CONFIGURATION
# ================================================================
BMW_FILE="/home/ga/BlenderDemos/BMW27.blend"
PROJECTS_DIR="/home/ga/BlenderProjects"
WORK_FILE="${PROJECTS_DIR}/render_scene.blend"
EXPECTED_BLEND="${PROJECTS_DIR}/composited_pipeline.blend"
EXPECTED_RENDER="${PROJECTS_DIR}/bmw_composited.png"

# Ensure projects directory exists
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# ================================================================
# CLEAN PREVIOUS OUTPUTS (before recording timestamp)
# ================================================================
rm -f "$EXPECTED_BLEND" 2>/dev/null || true
rm -f "$EXPECTED_RENDER" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# ================================================================
# VERIFY BMW DEMO EXISTS
# ================================================================
if [ ! -f "$BMW_FILE" ]; then
    echo "ERROR: BMW demo file not found at $BMW_FILE"
    echo "The environment setup (setup_blender.sh) should have downloaded it."
    exit 1
fi

# ================================================================
# KILL ANY RUNNING BLENDER (from post_start hook)
# ================================================================
echo "Stopping any existing Blender instances..."
pkill -f "blender" 2>/dev/null || true
sleep 2

# ================================================================
# PREPARE STARTING SCENE VIA HEADLESS BLENDER
# ================================================================
echo "Preparing starting scene from BMW demo..."

SETUP_SCRIPT=$(mktemp /tmp/setup_compositing.XXXXXX.py)
cat > "$SETUP_SCRIPT" << 'PYEOF'
import bpy
import json

# Open the BMW demo scene
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderDemos/BMW27.blend")

scene = bpy.context.scene
vl = bpy.context.view_layer

# --- Render Settings ---
# Set Cycles with 128 samples (agent must change to 64)
scene.render.engine = 'CYCLES'
scene.cycles.samples = 128
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 100

# --- Disable all extra render passes ---
vl.use_pass_z = False
vl.use_pass_mist = False
vl.use_pass_normal = False
vl.use_pass_diffuse_color = False
vl.use_pass_glossy_direct = False
vl.use_pass_ambient_occlusion = False
vl.use_pass_emission = False

# --- Reset Mist settings ---
if scene.world:
    scene.world.mist_settings.start = 0.0
    scene.world.mist_settings.depth = 0.0

# --- Reset Compositor to clean default ---
# Enable Use Nodes and create only the default Render Layers -> Composite link
scene.use_nodes = True
tree = scene.node_tree

# Remove all existing nodes
for node in list(tree.nodes):
    tree.nodes.remove(node)

# Add default Render Layers and Composite nodes
rl_node = tree.nodes.new('CompositorNodeRLayers')
rl_node.location = (-300, 300)
rl_node.name = "Render Layers"

comp_node = tree.nodes.new('CompositorNodeComposite')
comp_node.location = (300, 300)
comp_node.name = "Composite"

# Connect Image -> Image (default setup)
tree.links.new(rl_node.outputs['Image'], comp_node.inputs['Image'])

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/render_scene.blend")

# Report initial state
state = {
    "render_engine": scene.render.engine,
    "samples": scene.cycles.samples,
    "resolution": [scene.render.resolution_x, scene.render.resolution_y],
    "passes_ao": vl.use_pass_ambient_occlusion,
    "passes_mist": vl.use_pass_mist,
    "mist_start": scene.world.mist_settings.start if scene.world else -1,
    "mist_depth": scene.world.mist_settings.depth if scene.world else -1,
    "compositor_node_count": len(tree.nodes),
    "compositor_link_count": len(tree.links)
}

print("INITIAL_STATE_JSON:" + json.dumps(state))
PYEOF

SETUP_OUTPUT=$(/opt/blender/blender --background --python "$SETUP_SCRIPT" 2>&1)
INITIAL_LINE=$(echo "$SETUP_OUTPUT" | grep "^INITIAL_STATE_JSON:" | head -1)

if [ -n "$INITIAL_LINE" ]; then
    INITIAL_STATE="${INITIAL_LINE#INITIAL_STATE_JSON:}"
    echo "$INITIAL_STATE" > /tmp/initial_state.json
    echo "Initial state recorded."
else
    echo '{"error": "Could not extract initial state"}' > /tmp/initial_state.json
    echo "WARNING: Could not extract initial state from Blender output"
fi

rm -f "$SETUP_SCRIPT"

# Verify the working file was created
if [ ! -f "$WORK_FILE" ]; then
    echo "ERROR: Failed to create working blend file at $WORK_FILE"
    exit 1
fi

chown ga:ga "$WORK_FILE"

# ================================================================
# LAUNCH BLENDER WITH PREPARED SCENE
# ================================================================
echo "Launching Blender with prepared scene..."
pkill -f "blender" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 /opt/blender/blender '$WORK_FILE' &"

# Wait for Blender window to appear
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        echo "Blender window detected."
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
echo "Scene: BMW demo loaded as render_scene.blend"
echo "Compositor: clean default (Render Layers -> Composite)"
echo "Render passes: all disabled (agent must enable AO + Mist)"
echo "Samples: 128 (agent must change to 64)"
echo "Mist: unconfigured (Start=0, Depth=0)"
echo "Expected blend output: $EXPECTED_BLEND"
echo "Expected render output: $EXPECTED_RENDER"
