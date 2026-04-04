#!/bin/bash
echo "=== Exporting add_sphere_to_scene result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_BLEND="/home/ga/BlenderProjects/scene_with_sphere.blend"

# ================================================================
# GET INITIAL STATE
# ================================================================
INITIAL_SPHERE_COUNT="0"
INITIAL_OBJECT_COUNT="0"
INITIAL_MTIME="0"
INITIAL_EXISTS="false"

if [ -f /tmp/initial_state.json ]; then
    INITIAL_SPHERE_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_scene', {}).get('sphere_count', 0))" 2>/dev/null || echo "0")
    INITIAL_OBJECT_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_scene', {}).get('object_count', 0))" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('output_mtime', 0))" 2>/dev/null || echo "0")
    INITIAL_EXISTS=$(python3 -c "import json; v=json.load(open('/tmp/initial_state.json')).get('output_exists', False); print('true' if v else 'false')" 2>/dev/null || echo "false")
fi

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    CURRENT_MTIME=$(stat -c%Y "$OUTPUT_BLEND" 2>/dev/null || echo "0")

    # Check if file is valid blend file (magic bytes)
    IS_VALID_BLEND="false"
    MAGIC=$(head -c 7 "$OUTPUT_BLEND" 2>/dev/null | tr -d '\0')
    if [ "$MAGIC" = "BLENDER" ]; then
        IS_VALID_BLEND="true"
    fi

    # Check if file was modified/created
    FILE_CREATED="false"
    FILE_MODIFIED="false"
    if [ "$INITIAL_EXISTS" = "false" ]; then
        FILE_CREATED="true"
    elif [ "$CURRENT_MTIME" != "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi

    # Analyze the output blend file for spheres
    SCENE_ANALYSIS=$(python3 << 'PYEOF'
import subprocess
import json

script = '''
import bpy
import json

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/scene_with_sphere.blend")

objects = []
spheres = []

for obj in bpy.data.objects:
    obj_info = {
        "name": obj.name,
        "type": obj.type,
        "location": list(obj.location)
    }
    objects.append(obj_info)

    # Check if it's a sphere (by name or mesh structure)
    if "sphere" in obj.name.lower() or "Sphere" in obj.name:
        spheres.append(obj_info)
    elif obj.type == "MESH" and obj.data:
        # Check if mesh is sphere-like (has UV sphere structure)
        mesh = obj.data
        if hasattr(mesh, 'vertices') and len(mesh.vertices) > 100:
            # Check if vertices form a roughly spherical shape
            # UV spheres typically have many vertices
            spheres.append(obj_info)

result = {
    "object_count": len(bpy.data.objects),
    "sphere_count": len(spheres),
    "objects": objects,
    "spheres": spheres
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
        print('{"error": "no output", "object_count": 0, "sphere_count": 0, "objects": [], "spheres": []}')
except Exception as e:
    print(json.dumps({"error": str(e), "object_count": 0, "sphere_count": 0, "objects": [], "spheres": []}))
PYEOF
)

    CURRENT_OBJECT_COUNT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('object_count', 0))" 2>/dev/null || echo "0")
    CURRENT_SPHERE_COUNT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('sphere_count', 0))" 2>/dev/null || echo "0")
    SPHERES_JSON=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('spheres', [])))" 2>/dev/null || echo "[]")
    OBJECTS_JSON=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('objects', [])))" 2>/dev/null || echo "[]")
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CURRENT_MTIME="0"
    IS_VALID_BLEND="false"
    FILE_CREATED="false"
    FILE_MODIFIED="false"
    CURRENT_OBJECT_COUNT="0"
    CURRENT_SPHERE_COUNT="0"
    SPHERES_JSON="[]"
    OBJECTS_JSON="[]"
fi

# Check if a new sphere was added
SPHERE_ADDED="false"
if [ "$CURRENT_SPHERE_COUNT" -gt "$INITIAL_SPHERE_COUNT" ]; then
    SPHERE_ADDED="true"
fi

# ================================================================
# CHECK BLENDER STATE
# ================================================================
BLENDER_RUNNING="false"
BLENDER_WINDOW_TITLE=""

if pgrep -x "blender" > /dev/null 2>&1; then
    BLENDER_RUNNING="true"
fi

BLENDER_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "blender" || echo "")
if [ -n "$BLENDER_WINDOWS" ]; then
    BLENDER_WINDOW_TITLE=$(echo "$BLENDER_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_BLEND",
    "is_valid_blend": $IS_VALID_BLEND,
    "file_created": $FILE_CREATED,
    "file_modified": $FILE_MODIFIED,
    "initial_object_count": $INITIAL_OBJECT_COUNT,
    "current_object_count": $CURRENT_OBJECT_COUNT,
    "initial_sphere_count": $INITIAL_SPHERE_COUNT,
    "current_sphere_count": $CURRENT_SPHERE_COUNT,
    "sphere_added": $SPHERE_ADDED,
    "spheres": $SPHERES_JSON,
    "objects": $OBJECTS_JSON,
    "blender_was_running": $BLENDER_RUNNING,
    "blender_window_title": "$BLENDER_WINDOW_TITLE",
    "screenshot_path": "/tmp/task_end.png",
    "initial_screenshot_path": "/tmp/task_start.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
