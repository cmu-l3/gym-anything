#!/bin/bash
echo "=== Setting up Grease Pencil Line Art task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ================================================================
# PREPARE SCENE
# ================================================================
# We need the BMW demo file. It should be in Demos or Projects.
DEMO_PATH="/home/ga/BlenderDemos/BMW27.blend"
WORK_PATH="/home/ga/BlenderProjects/bmw_source.blend"
OUTPUT_PATH="/home/ga/BlenderProjects/bmw_line_art.blend"

# Ensure clean state
rm -f "$OUTPUT_PATH"

if [ -f "$DEMO_PATH" ]; then
    cp "$DEMO_PATH" "$WORK_PATH"
    echo "Copied BMW demo to workspace."
elif [ -f "/home/ga/BlenderProjects/render_scene.blend" ]; then
    # Fallback if specific demo path failed but setup_blender.sh put it here
    cp "/home/ga/BlenderProjects/render_scene.blend" "$WORK_PATH"
    echo "Used render_scene.blend as source."
else
    # Last resort fallback: Create a simple scene with some geometry to outline
    echo "Warning: BMW demo not found. Creating fallback geometry."
    cat > /tmp/create_fallback.py << 'EOF'
import bpy
bpy.ops.mesh.primitive_monkey_add(size=2, location=(0,0,1))
bpy.context.active_object.name = "Suzanne"
# Put it in a collection named BMW for consistency with task desc
col = bpy.data.collections.new("BMW")
bpy.context.scene.collection.children.link(col)
col.objects.link(bpy.context.active_object)
bpy.context.scene.collection.objects.unlink(bpy.context.active_object)
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/bmw_source.blend")
EOF
    /opt/blender/blender --background --python /tmp/create_fallback.py
fi

chown ga:ga "$WORK_PATH"

# ================================================================
# LAUNCH BLENDER
# ================================================================
echo "Launching Blender..."
if ! pgrep -f "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$WORK_PATH' &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
            echo "Blender window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Capture initial state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="