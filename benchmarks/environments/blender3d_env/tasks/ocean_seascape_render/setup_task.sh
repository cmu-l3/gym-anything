#!/bin/bash
set -e
echo "=== Setting up Ocean Seascape task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Establish clean state
PROJECT_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECT_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Remove previous outputs if they exist
rm -f "$PROJECT_DIR/ocean_scene.blend"
rm -f "$PROJECT_DIR/ocean_render.png"

# 2. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Create a clean startup file (Empty scene)
# We create a python script to reset the scene and save it as start.blend
cat > /tmp/create_empty.py << 'PYEOF'
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
# Set default render settings for speed
bpy.context.scene.render.engine = 'BLENDER_EEVEE_NEXT'
bpy.context.scene.render.resolution_x = 1920
bpy.context.scene.render.resolution_y = 1080
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/start.blend")
PYEOF

su - ga -c "/opt/blender/blender --background --python /tmp/create_empty.py" > /dev/null 2>&1

# 4. Launch Blender with the empty start file
echo "Launching Blender..."
if ! pgrep -f "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/start.blend &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "blender"; then
            echo "Blender window detected"
            break
        fi
        sleep 1
    done
fi

# 5. Maximize and Focus
focus_blender
sleep 1
maximize_blender
sleep 1

# 6. Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="