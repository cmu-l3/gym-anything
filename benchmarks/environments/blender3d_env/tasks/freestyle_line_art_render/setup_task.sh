#!/bin/bash
echo "=== Setting up freestyle_line_art_render task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
DEMO_BLEND="/home/ga/BlenderDemos/BMW27.blend"
WORK_BLEND="/home/ga/BlenderProjects/render_scene.blend"
PROJECTS_DIR="/home/ga/BlenderProjects"

# Ensure projects directory exists
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# ================================================================
# PREPARE SCENE: Ensure Freestyle is OFF and Background is GREY
# ================================================================
echo "Preparing scene state..."

# Create a preparation script
PREP_SCRIPT=$(mktemp /tmp/prep_scene.XXXXXX.py)
cat > "$PREP_SCRIPT" << 'PYEOF'
import bpy

# Open the demo file
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderDemos/BMW27.blend")

scene = bpy.context.scene

# 1. Disable Freestyle explicitly
scene.render.use_freestyle = False

# 2. Set World Background to Grey (0.5)
if scene.world:
    if scene.world.use_nodes:
        # Try to find background node
        bg_node = None
        for node in scene.world.node_tree.nodes:
            if node.type == 'BACKGROUND':
                bg_node = node
                break
        if bg_node:
            bg_node.inputs['Color'].default_value = (0.5, 0.5, 0.5, 1.0)
    else:
        scene.world.color = (0.5, 0.5, 0.5)

# 3. Reset Resolution (just in case)
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 50  # Lower percentage for preview speed, agent should fix if needed

# Save to the working path
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/render_scene.blend")
print("Scene prepared and saved.")
PYEOF

# Run preparation script
/opt/blender/blender --background --python "$PREP_SCRIPT" > /dev/null 2>&1
rm -f "$PREP_SCRIPT"

# Clean up any previous outputs
rm -f "/home/ga/BlenderProjects/line_art_render.png"
rm -f "/home/ga/BlenderProjects/freestyle_setup.blend"

# ================================================================
# LAUNCH BLENDER
# ================================================================
echo "Checking Blender status..."
pkill -f "blender" 2>/dev/null || true
sleep 1

echo "Starting Blender with prepared scene..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$WORK_BLEND' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Focus and maximize
focus_blender
sleep 1
maximize_blender
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="