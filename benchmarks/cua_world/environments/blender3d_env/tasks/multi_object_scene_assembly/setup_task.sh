#!/bin/bash
echo "=== Setting up multi_object_scene_assembly task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

OUTPUT_BLEND="/home/ga/BlenderProjects/showcase_scene.blend"
EMPTY_BLEND="/home/ga/BlenderProjects/empty_showcase.blend"

# Ensure projects directory exists
mkdir -p /home/ga/BlenderProjects
chown -R ga:ga /home/ga/BlenderProjects

# Remove any existing output file to ensure clean state
rm -f "$OUTPUT_BLEND"

# ================================================================
# CREATE EMPTY SCENE VIA BLENDER PYTHON (headless)
# ================================================================
echo "Creating empty showcase scene with camera + light..."

SETUP_RESULT=$(python3 << 'PYEOF'
import subprocess
import json

script = '''
import bpy
import json
import math

# Start with a completely empty scene
bpy.ops.wm.read_homefile(use_empty=True)

# Delete anything that might exist
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=True)

# Add a camera
bpy.ops.object.camera_add(location=(7.0, -6.0, 5.0))
camera = bpy.context.active_object
camera.name = "Camera"
# Point camera toward origin
camera.rotation_euler = (math.radians(63.6), 0.0, math.radians(46.7))
bpy.context.scene.camera = camera

# Add a Sun light
bpy.ops.object.light_add(type='SUN', location=(5.0, 5.0, 10.0))
sun = bpy.context.active_object
sun.name = "Sun"
sun.data.energy = 3.0

# Set render engine to EEVEE for speed
bpy.context.scene.render.engine = 'BLENDER_EEVEE_NEXT'
bpy.context.scene.render.resolution_x = 1920
bpy.context.scene.render.resolution_y = 1080

# Save the empty scene
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/empty_showcase.blend")

# Count objects for verification
result = {
    "object_count": len(bpy.data.objects),
    "mesh_count": len(bpy.data.meshes),
    "material_count": len(bpy.data.materials),
    "camera_count": len([o for o in bpy.data.objects if o.type == "CAMERA"]),
    "light_count": len([o for o in bpy.data.objects if o.type == "LIGHT"]),
    "objects": [{"name": o.name, "type": o.type} for o in bpy.data.objects]
}
print("JSON:" + json.dumps(result))
'''

try:
    result = subprocess.run(
        ["/opt/blender/blender", "--background", "--python-expr", script],
        capture_output=True, text=True, timeout=120
    )
    for line in result.stdout.split('\n'):
        if line.startswith('JSON:'):
            print(line[5:])
            break
    else:
        print('{"error": "no output", "object_count": 0, "mesh_count": 0, "material_count": 0}')
except Exception as e:
    print(json.dumps({"error": str(e), "object_count": 0, "mesh_count": 0, "material_count": 0}))
PYEOF
)

echo "Setup result: $SETUP_RESULT"

# ================================================================
# RECORD INITIAL STATE
# ================================================================
cat > /tmp/initial_state.json << EOF
{
    "empty_blend": "$EMPTY_BLEND",
    "output_blend": "$OUTPUT_BLEND",
    "initial_scene": $SETUP_RESULT,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state saved to /tmp/initial_state.json"
cat /tmp/initial_state.json

# Fix ownership of the empty blend file
chown ga:ga "$EMPTY_BLEND" 2>/dev/null || true

# ================================================================
# LAUNCH BLENDER WITH EMPTY SCENE
# ================================================================
echo "Checking Blender status..."
BLENDER_RUNNING=$(is_blender_running)

if [ "$BLENDER_RUNNING" = "true" ]; then
    echo "Killing existing Blender process..."
    pkill -9 -x blender 2>/dev/null || true
    sleep 2
fi

echo "Starting Blender with empty showcase scene..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$EMPTY_BLEND' &"
sleep 8

# Focus and maximize Blender window
focus_blender
sleep 1
maximize_blender
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Build a material showcase scene with 5 primitives, materials, ground plane, and 2+ lights"
echo "Save to: $OUTPUT_BLEND"
