#!/bin/bash
echo "=== Setting up procedural_rust_material task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# ================================================================
# CONFIGURATION
# ================================================================
SOURCE_BLEND="/home/ga/BlenderDemos/BMW27.blend"
START_BLEND="/home/ga/BlenderProjects/rust_start.blend"
EXPECTED_BLEND="/home/ga/BlenderProjects/rust_bmw.blend"
EXPECTED_RENDER="/home/ga/BlenderProjects/rust_render.png"
PROJECTS_DIR="/home/ga/BlenderProjects"

# Ensure projects directory exists
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Remove any existing output files BEFORE recording timestamp
rm -f "$EXPECTED_BLEND" 2>/dev/null || true
rm -f "$EXPECTED_RENDER" 2>/dev/null || true
rm -f "$START_BLEND" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time

# ================================================================
# PREPARE STARTING SCENE VIA HEADLESS BLENDER PYTHON
# ================================================================
# Opens BMW27.blend, identifies the car body mesh, renames it to
# 'CarBody', replaces its material with a plain grey Principled BSDF,
# and saves the prepared scene.
echo "Preparing BMW scene with clean CarBody material..."

SETUP_SCRIPT=$(mktemp /tmp/setup_rust_task.XXXXXX.py)
cat > "$SETUP_SCRIPT" << 'PYEOF'
import bpy
import json

# Open the source BMW scene
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderDemos/BMW27.blend")

# ----------------------------------------------------------------
# Find the car body shell mesh by name
# In BMW27.blend, the car body is named 'carShell'
# ----------------------------------------------------------------
car_body = bpy.data.objects.get("carShell")

if car_body is None:
    # Fallback: search for any object with 'shell' or 'body' or 'car' in name
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and any(k in obj.name.lower() for k in ['shell', 'body', 'car']):
            car_body = obj
            break

if car_body is None:
    print("ERROR: Could not find car body mesh in BMW scene")
    raise SystemExit(1)

# Rename to CarBody
original_name = car_body.name
car_body.name = "CarBody"
largest_mesh = car_body
largest_vcount = len(car_body.data.vertices)

# ----------------------------------------------------------------
# Replace its material with a single plain Principled BSDF
# ----------------------------------------------------------------
# Clear all existing material slots
largest_mesh.data.materials.clear()

# Create a new simple material
mat = bpy.data.materials.new(name="CarBodyMaterial")
mat.use_nodes = True
largest_mesh.data.materials.append(mat)

# The default node tree already has Principled BSDF + Material Output
# connected. Reset BSDF to plain grey defaults.
bsdf = mat.node_tree.nodes.get("Principled BSDF")
if bsdf:
    bsdf.inputs["Base Color"].default_value = (0.4, 0.4, 0.4, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.5

# ----------------------------------------------------------------
# Ensure render settings are reasonable
# ----------------------------------------------------------------
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 50  # effective 960x540

# ----------------------------------------------------------------
# Ensure the standard "Shading" workspace exists
# BMW27.blend has custom workspaces that may lack a Shading layout.
# We duplicate the current workspace and rename it, then the agent
# can switch the editor type to Shader Editor within it.
# ----------------------------------------------------------------
if "Shading" not in bpy.data.workspaces:
    # Duplicate current workspace
    current_ws = bpy.context.window.workspace
    bpy.ops.workspace.duplicate()
    new_ws = bpy.context.window.workspace
    new_ws.name = "Shading"

    # Switch back to original workspace so the agent starts in the 3D view
    bpy.context.window.workspace = current_ws

# ----------------------------------------------------------------
# Record initial state
# ----------------------------------------------------------------
node_names = []
if mat.use_nodes and mat.node_tree:
    node_names = [n.name for n in mat.node_tree.nodes]

link_count = 0
if mat.use_nodes and mat.node_tree:
    link_count = len(mat.node_tree.links)

initial_state = {
    "source_blend": "/home/ga/BlenderDemos/BMW27.blend",
    "car_body_object": "CarBody",
    "car_body_original_name": original_name,
    "car_body_vertex_count": largest_vcount,
    "material_name": "CarBodyMaterial",
    "initial_node_count": len(node_names),
    "initial_node_names": node_names,
    "initial_link_count": link_count,
    "render_engine": scene.render.engine,
    "render_samples": scene.cycles.samples,
    "resolution": [scene.render.resolution_x, scene.render.resolution_y],
    "resolution_percentage": scene.render.resolution_percentage,
    "total_objects": len(bpy.data.objects)
}

print("INITIAL_STATE_JSON:" + json.dumps(initial_state))

# Save the prepared scene
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/rust_start.blend")
PYEOF

# Run the setup script headlessly
SETUP_OUTPUT=$(/opt/blender/blender --background --python "$SETUP_SCRIPT" 2>/dev/null)
INITIAL_STATE_LINE=$(echo "$SETUP_OUTPUT" | grep '^INITIAL_STATE_JSON:' | head -1)

if [ -n "$INITIAL_STATE_LINE" ]; then
    INITIAL_STATE="${INITIAL_STATE_LINE#INITIAL_STATE_JSON:}"
else
    echo "WARNING: Could not extract initial state from Blender output"
    INITIAL_STATE='{"car_body_object": "CarBody", "material_name": "CarBodyMaterial", "initial_node_count": 2, "initial_link_count": 1}'
fi

rm -f "$SETUP_SCRIPT"

# ================================================================
# SAVE INITIAL STATE
# ================================================================
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)",
    "source_blend": "$SOURCE_BLEND",
    "start_blend": "$START_BLEND",
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
# KILL EXISTING BLENDER AND LAUNCH WITH PREPARED SCENE
# ================================================================
echo "Stopping any existing Blender instances..."
pkill -9 -x blender 2>/dev/null || true
sleep 2

echo "Launching Blender with prepared scene..."
if [ -f "$START_BLEND" ]; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$START_BLEND' &"
else
    echo "WARNING: Start blend file not created, using source..."
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$SOURCE_BLEND' &"
fi
sleep 5

# Focus and maximize Blender window
focus_blender 2>/dev/null || true
sleep 1
maximize_blender 2>/dev/null || true
sleep 1

# Dismiss splash screen if present
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Scene: BMW car model loaded with CarBody object having plain grey material"
echo "Agent must build a procedural rust shader in the Shader Editor"
echo "Expected blend output: $EXPECTED_BLEND"
echo "Expected render output: $EXPECTED_RENDER"
