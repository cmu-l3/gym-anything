#!/bin/bash
set -e
echo "=== Setting up Cinematic Compositing task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECTS_DIR="/home/ga/BlenderProjects"
DEMOS_DIR="/home/ga/BlenderDemos"
SOURCE_BLEND="$PROJECTS_DIR/composite_source.blend"

mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Remove any previous task outputs to ensure clean state
rm -f "$PROJECTS_DIR/cinematic_composite.png"
rm -f "$PROJECTS_DIR/compositing_setup.blend"
rm -f /tmp/task_result.json
rm -f /tmp/initial_state.json

# Determine source scene (prefer BMW27 as it's the standard benchmark)
if [ -f "$DEMOS_DIR/BMW27.blend" ]; then
    BASE_SCENE="$DEMOS_DIR/BMW27.blend"
    echo "Using BMW27.blend as source scene"
elif [ -f "$PROJECTS_DIR/baseline_scene.blend" ]; then
    BASE_SCENE="$PROJECTS_DIR/baseline_scene.blend"
    echo "Using baseline_scene.blend as source scene"
else
    # Fallback: Create a simple scene if no demos exist
    echo "Creating fallback scene..."
    /opt/blender/blender --background --python-expr "
import bpy
bpy.ops.mesh.primitive_cube_add()
bpy.ops.object.camera_add(location=(5, -5, 5))
bpy.ops.object.constraint_add(type='TRACK_TO')
bpy.context.object.constraints['Track To'].target = bpy.data.objects['Cube']
bpy.ops.wm.save_as_mainfile(filepath='$PROJECTS_DIR/baseline_scene.blend')
"
    BASE_SCENE="$PROJECTS_DIR/baseline_scene.blend"
fi

# Prepare the source scene: disable compositor, set low render settings
# This ensures the agent starts from a clean slate
cat > /tmp/prepare_composite_scene.py << 'PREP_EOF'
import bpy
import json
import sys

# Get the source file path from command line args
args = sys.argv[sys.argv.index("--") + 1:]
source_path = args[0]
output_path = args[1]

# Open the source scene
bpy.ops.wm.open_mainfile(filepath=source_path)

scene = bpy.context.scene

# --- Disable compositor ---
scene.use_nodes = False

# If a node tree exists, clear it to default state
if scene.node_tree:
    scene.node_tree.nodes.clear()
    scene.node_tree.links.clear()

# --- Set low render settings for fast rendering ---
scene.render.engine = 'CYCLES'
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 50  # 960x540 actual
scene.cycles.samples = 32
scene.cycles.use_denoising = True

# Ensure CPU rendering for compatibility if GPU fails
# scene.cycles.device = 'CPU'

# Set output format
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGB'
scene.render.image_settings.compression = 15

# Make sure there's a camera
if not scene.camera:
    cameras = [o for o in bpy.data.objects if o.type == 'CAMERA']
    if cameras:
        scene.camera = cameras[0]

# Record initial state
initial_state = {
    "source_scene": source_path,
    "use_nodes": scene.use_nodes,
    "samples": scene.cycles.samples,
    "has_camera": scene.camera is not None
}

with open("/tmp/initial_state.json", "w") as f:
    json.dump(initial_state, f, indent=2)

# Save prepared scene
bpy.ops.wm.save_as_mainfile(filepath=output_path)
print(f"Prepared scene saved to: {output_path}")
PREP_EOF

# Run preparation script
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/prepare_composite_scene.py -- '$BASE_SCENE' '$SOURCE_BLEND'" > /dev/null 2>&1

# Verify source scene was created
if [ ! -f "$SOURCE_BLEND" ]; then
    echo "ERROR: Failed to create source scene"
    exit 1
fi

chown ga:ga "$SOURCE_BLEND"
echo "Source scene prepared: $SOURCE_BLEND"

# Kill any existing Blender instances
pkill -f blender 2>/dev/null || true
sleep 2

# Launch Blender with the prepared scene
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$SOURCE_BLEND' &"

# Wait for Blender window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

sleep 3

# Maximize Blender window
maximize_blender

# Focus Blender
focus_blender

sleep 2

# Dismiss any startup splash screen
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Compositing task setup complete ==="