#!/bin/bash
echo "=== Setting up add_sphere_to_scene task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record initial scene state using Blender Python API
SOURCE_BLEND="/home/ga/BlenderProjects/baseline_scene.blend"
OUTPUT_BLEND="/home/ga/BlenderProjects/scene_with_sphere.blend"

# Get initial object list from the source blend file
INITIAL_STATE=$(python3 << 'PYEOF'
import subprocess
import json

script = '''
import bpy
import json

# Open the source file
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")

objects = []
for obj in bpy.data.objects:
    objects.append({
        "name": obj.name,
        "type": obj.type,
        "location": list(obj.location)
    })

result = {
    "object_count": len(bpy.data.objects),
    "objects": objects,
    "sphere_count": len([o for o in bpy.data.objects if "sphere" in o.name.lower()])
}
print("JSON:" + json.dumps(result))
'''

try:
    result = subprocess.run(
        ["/opt/blender/blender", "--background", "--python-expr", script],
        capture_output=True, text=True, timeout=60
    )
    for line in result.stdout.split('\n'):
        if line.startswith('JSON:'):
            print(line[5:])
            break
    else:
        print('{"error": "no output", "object_count": 0, "objects": [], "sphere_count": 0}')
except Exception as e:
    print(json.dumps({"error": str(e), "object_count": 0, "objects": [], "sphere_count": 0}))
PYEOF
)

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "source_blend": "$SOURCE_BLEND",
    "output_blend": "$OUTPUT_BLEND",
    "initial_scene": $INITIAL_STATE,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial scene state saved to /tmp/initial_state.json"
cat /tmp/initial_state.json

# Remove any existing output file to ensure clean state
rm -f "$OUTPUT_BLEND"

# Make sure Blender is running with the source scene
echo "Checking Blender status..."
BLENDER_RUNNING=$(is_blender_running)

if [ "$BLENDER_RUNNING" = "false" ]; then
    echo "Starting Blender with source scene..."
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$SOURCE_BLEND' &"
    sleep 5
else
    # Blender is running, open the source file
    echo "Blender is running, opening source file..."
fi

# Focus and maximize Blender window
focus_blender
sleep 1
maximize_blender
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Add a UV sphere to the scene and save as $OUTPUT_BLEND"
