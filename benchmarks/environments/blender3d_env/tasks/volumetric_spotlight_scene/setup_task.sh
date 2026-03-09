#!/bin/bash
set -e
echo "=== Setting up Volumetric Spotlight Scene Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Define paths
BASELINE_SCENE="/home/ga/BlenderProjects/baseline_scene.blend"
OUTPUT_SCENE="/home/ga/BlenderProjects/volumetric_scene.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/volumetric_render.png"

# Ensure baseline scene exists (created by env setup, but verify)
if [ ! -f "$BASELINE_SCENE" ]; then
    echo "Regenerating baseline scene..."
    # Fallback generation script
    cat > /tmp/gen_base.py << 'EOF'
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0,0,1))
cube = bpy.context.active_object
cube.name = "BaseCube"
mat = bpy.data.materials.new(name="RedMat")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.8, 0.1, 0.1, 1)
cube.data.materials.append(mat)
bpy.ops.object.light_add(type='SUN', location=(5,5,10))
bpy.ops.object.camera_add(location=(7,-6,5))
cam = bpy.context.active_object
cam.rotation_euler = (1.1, 0, 0.8)
bpy.context.scene.camera = cam
bpy.ops.mesh.primitive_plane_add(size=20)
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 32
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")
EOF
    /opt/blender/blender --background --python /tmp/gen_base.py
fi

# Clean up previous outputs
rm -f "$OUTPUT_SCENE"
rm -f "$OUTPUT_RENDER"

# Start Blender with baseline scene
echo "Starting Blender..."
if ! pgrep -f "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$BASELINE_SCENE' &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
            echo "Blender window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="