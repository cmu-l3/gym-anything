#!/bin/bash
set -e
echo "=== Setting up physical_sky_reference_spheres task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Configuration
BASELINE_SCENE="/home/ga/BlenderProjects/baseline_scene.blend"
PROJECT_SCENE="/home/ga/BlenderProjects/sky_setup_start.blend"
OUTPUT_BLEND="/home/ga/BlenderProjects/sky_reference_setup.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/sky_reference_render.png"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure baseline scene exists
if [ ! -f "$BASELINE_SCENE" ]; then
    echo "Creating baseline scene..."
    # Fallback creation if environment setup failed
    su - ga -c "/opt/blender/blender --background --python-expr '
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
bpy.context.active_object.name = \"BaseCube\"
bpy.ops.object.camera_add(location=(0, -8, 5), rotation=(1.1, 0, 0))
bpy.context.scene.camera = bpy.context.active_object
bpy.ops.object.light_add(type=\"SUN\", location=(5, 5, 10))
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
bpy.context.scene.render.engine = \"CYCLES\"
bpy.context.scene.cycles.samples = 32
bpy.ops.wm.save_as_mainfile(filepath=\"$BASELINE_SCENE\")
'"
fi

# Copy baseline to a working file
cp "$BASELINE_SCENE" "$PROJECT_SCENE"
chown ga:ga "$PROJECT_SCENE"

# Clean up previous outputs
rm -f "$OUTPUT_BLEND" "$OUTPUT_RENDER"

# Start Blender
echo "Starting Blender..."
if ! pgrep -f "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$PROJECT_SCENE' &"
    sleep 10
fi

# Focus and maximize
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="