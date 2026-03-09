#!/bin/bash
set -e
echo "=== Exporting particle_fur_system_setup results ==="

source /workspace/scripts/task_utils.sh

BLEND_FILE="/home/ga/BlenderProjects/fur_setup.blend"
RENDER_FILE="/home/ga/BlenderProjects/fur_render.png"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Check file existence and timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BLEND_EXISTS="false"
BLEND_MTIME="0"
RENDER_EXISTS="false"
RENDER_MTIME="0"
RENDER_SIZE="0"

if [ -f "$BLEND_FILE" ]; then
    BLEND_EXISTS="true"
    BLEND_MTIME=$(stat -c%Y "$BLEND_FILE" 2>/dev/null || echo "0")
fi

if [ -f "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    RENDER_MTIME=$(stat -c%Y "$RENDER_FILE" 2>/dev/null || echo "0")
    RENDER_SIZE=$(stat -c%s "$RENDER_FILE" 2>/dev/null || echo "0")
fi

# Analyze the blend file with Blender Python API
# We run this even if blend file doesn't exist (it returns empty/default values)
cat > /tmp/analyze_fur.py << 'PYEOF'
import bpy
import json
import sys

blend_path = "/home/ga/BlenderProjects/fur_setup.blend"
result = {
    "blend_file_valid": False,
    "suzanne_found": False,
    "suzanne_vertex_count": 0,
    "suzanne_location": [0, 0, 0],
    "particle_systems": [],
    "hair_system_found": False,
    "hair_count": 0,
    "hair_length": 0.0,
    "child_type": "NONE",
    "child_display_count": 0,
    "child_render_count": 0,
    "material_found": False,
    "material_base_color": [0, 0, 0, 1],
    "material_has_principled": False,
    "all_objects": [],
    "total_particle_systems": 0
}

try:
    bpy.ops.wm.open_mainfile(filepath=blend_path)
    result["blend_file_valid"] = True
except Exception as e:
    result["error"] = str(e)
    print("RESULT_JSON:" + json.dumps(result))
    sys.exit(0)

# Find Suzanne/Monkey mesh
suzanne_obj = None
for obj in bpy.data.objects:
    obj_info = {
        "name": obj.name,
        "type": obj.type,
        "location": list(obj.location),
        "particle_system_count": len(obj.particle_systems) if hasattr(obj, 'particle_systems') else 0
    }
    if obj.type == 'MESH':
        obj_info["vertex_count"] = len(obj.data.vertices)
    result["all_objects"].append(obj_info)

    name_lower = obj.name.lower()
    if ("suzanne" in name_lower or "monkey" in name_lower) and obj.type == 'MESH':
        suzanne_obj = obj
        result["suzanne_found"] = True
        result["suzanne_vertex_count"] = len(obj.data.vertices)
        result["suzanne_location"] = [round(v, 4) for v in obj.location]

# If no object named Suzanne/Monkey, check for any mesh with hair particles and ~500 verts
if suzanne_obj is None:
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and len(obj.particle_systems) > 0:
            vcount = len(obj.data.vertices)
            if vcount >= 400 and vcount <= 600:
                suzanne_obj = obj
                result["suzanne_found"] = True
                result["suzanne_vertex_count"] = vcount
                result["suzanne_location"] = [round(v, 4) for v in obj.location]
                break

# Analyze particle systems
if suzanne_obj is not None:
    result["total_particle_systems"] = len(suzanne_obj.particle_systems)
    for ps in suzanne_obj.particle_systems:
        settings = ps.settings
        ps_info = {
            "name": ps.name,
            "type": settings.type,
            "count": settings.count,
            "hair_length": round(settings.hair_length, 4),
            "child_type": settings.child_type,
            "child_nbr": settings.child_nbr,  # display amount
            "rendered_child_count": settings.rendered_child_count
        }
        result["particle_systems"].append(ps_info)

        if settings.type == 'HAIR':
            result["hair_system_found"] = True
            result["hair_count"] = settings.count
            result["hair_length"] = round(settings.hair_length, 4)
            result["child_type"] = settings.child_type
            result["child_display_count"] = settings.child_nbr
            result["child_render_count"] = settings.rendered_child_count

    # Check materials
    if len(suzanne_obj.data.materials) > 0:
        result["material_found"] = True
        for mat in suzanne_obj.data.materials:
            if mat and mat.use_nodes:
                for node in mat.node_tree.nodes:
                    if node.type == 'BSDF_PRINCIPLED':
                        result["material_has_principled"] = True
                        bc = node.inputs["Base Color"].default_value
                        result["material_base_color"] = [round(bc[0], 4), round(bc[1], 4), round(bc[2], 4), round(bc[3], 4)]
                        break
                break

print("RESULT_JSON:" + json.dumps(result))
PYEOF

SCENE_DATA="{}"
if [ "$BLEND_EXISTS" = "true" ]; then
    BLENDER_OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_fur.py 2>/dev/null || echo "")
    SCENE_DATA=$(echo "$BLENDER_OUTPUT" | grep "^RESULT_JSON:" | sed 's/^RESULT_JSON://' | head -1)
    if [ -z "$SCENE_DATA" ]; then
        SCENE_DATA='{"error": "Could not parse Blender output"}'
    fi
fi

# Check render image validity
RENDER_VALID="false"
RENDER_WIDTH="0"
RENDER_HEIGHT="0"
if [ "$RENDER_EXISTS" = "true" ]; then
    IMG_INFO=$(python3 -c "
from PIL import Image
import json
try:
    img = Image.open('$RENDER_FILE')
    print(json.dumps({'valid': True, 'width': img.width, 'height': img.height, 'format': img.format}))
except Exception as e:
    print(json.dumps({'valid': False, 'error': str(e)}))
" 2>/dev/null || echo '{"valid": false}')
    
    RENDER_VALID=$(echo "$IMG_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('valid','false'))" 2>/dev/null || echo "false")
    RENDER_WIDTH=$(echo "$IMG_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('width',0))" 2>/dev/null || echo "0")
    RENDER_HEIGHT=$(echo "$IMG_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('height',0))" 2>/dev/null || echo "0")
fi

# Compose final result
python3 << COMPOSE_EOF
import json
import os

try:
    scene_data_str = '''$SCENE_DATA'''
    if not scene_data_str:
        scene_data = {}
    else:
        scene_data = json.loads(scene_data_str)
except Exception as e:
    scene_data = {"error": f"JSON parse error: {e}"}

result = {
    "task_start_time": $TASK_START,
    "blend_file": {
        "exists": $BLEND_EXISTS,
        "mtime": $BLEND_MTIME,
        "newer_than_start": $BLEND_MTIME > $TASK_START
    },
    "render_file": {
        "exists": $RENDER_EXISTS,
        "mtime": $RENDER_MTIME,
        "size_bytes": $RENDER_SIZE,
        "size_kb": round($RENDER_SIZE / 1024, 2),
        "valid_image": "$RENDER_VALID" == "True",
        "width": $RENDER_WIDTH,
        "height": $RENDER_HEIGHT,
        "newer_than_start": $RENDER_MTIME > $TASK_START
    },
    "scene_analysis": scene_data
}

with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
COMPOSE_EOF

# Set permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete. Results written to $RESULT_FILE ==="