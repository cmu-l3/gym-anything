#!/bin/bash
set -e
echo "=== Setting up render_passes_exr_export task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Paths
DEMO_SOURCE="/home/ga/BlenderDemos/BMW27.blend"
WORK_FILE="/home/ga/BlenderProjects/render_scene.blend"
PROJECTS_DIR="/home/ga/BlenderProjects"

# Ensure directories exist
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Clean up previous runs
rm -f /home/ga/BlenderProjects/bmw_passes.exr
rm -f /home/ga/BlenderProjects/bmw_vfx_setup.blend

# Prepare the starting scene
# We copy the official BMW demo and deliberately RESET/DISABLE all render passes
# and set output to PNG to ensure the agent has to do the work.
if [ -f "$DEMO_SOURCE" ]; then
    echo "Using BMW27 demo source..."
    cp "$DEMO_SOURCE" "$WORK_FILE"
elif [ -f "/home/ga/BlenderProjects/render_scene.blend" ]; then
    echo "Using existing render_scene.blend..."
    cp "/home/ga/BlenderProjects/render_scene.blend" "$WORK_FILE"
else
    # Fallback if specific demo missing (should not happen in this env)
    echo "WARNING: BMW Demo not found, creating placeholder..."
    /opt/blender/blender --background --python-expr "import bpy; bpy.ops.wm.save_as_mainfile(filepath='$WORK_FILE')"
fi

chown ga:ga "$WORK_FILE"

# Python script to reset scene state (disable passes, set PNG)
cat > /tmp/reset_scene.py << 'PYEOF'
import bpy
import json

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/render_scene.blend")
scene = bpy.context.scene
vl = scene.view_layers[0]

# 1. Disable all passes we care about
vl.use_pass_z = False
vl.use_pass_mist = False
vl.use_pass_normal = False
vl.use_pass_diffuse_color = False
vl.use_pass_glossy_direct = False
vl.use_pass_ambient_occlusion = False

# 2. Reset Output to PNG 8-bit
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_depth = '8'

# 3. Optimize render settings for speed (agent needs to render)
scene.render.engine = 'CYCLES'
scene.cycles.samples = 16  # Low samples for speed
scene.render.resolution_percentage = 50 # 50% res

# Save the reset file
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/render_scene.blend")

# Record initial state
state = {
    "passes": {
        "z": vl.use_pass_z,
        "mist": vl.use_pass_mist
    },
    "format": scene.render.image_settings.file_format
}
print("RESET_COMPLETE")
PYEOF

echo "Resetting scene configuration..."
su - ga -c "/opt/blender/blender --background --python /tmp/reset_scene.py" > /dev/null

# Launch Blender with the clean file
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$WORK_FILE' &"

# Wait for window
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="