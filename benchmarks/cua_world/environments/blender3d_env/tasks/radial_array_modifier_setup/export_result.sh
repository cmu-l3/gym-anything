#!/bin/bash
set -e
echo "=== Exporting radial_array_modifier_setup results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

OUTPUT_BLEND="/home/ga/BlenderProjects/fan_assembly.blend"
RESULT_FILE="/tmp/task_result.json"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED=0
FILE_VALID="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_BLEND" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    FILE_MODIFIED=$(stat -c%Y "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    
    # Check magic bytes
    MAGIC=$(head -c 7 "$OUTPUT_BLEND" 2>/dev/null | tr -d '\0')
    if [ "$MAGIC" = "BLENDER" ]; then
        FILE_VALID="true"
    fi

    if [ "$FILE_MODIFIED" -gt "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Run Blender headless to analyze scene
# We extract: Empties (rotation), Meshes (dims), Modifiers (Array settings)
cat > /tmp/analyze_fan.py << 'ANALYSIS_EOF'
import bpy
import json
import math
import sys

# Open the blend file
try:
    blend_path = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.open_mainfile(filepath=blend_path)
except:
    print("RESULT_JSON:{\"error\": \"Could not open file\"}")
    sys.exit(0)

result = {
    "objects": [],
    "empties": [],
    "array_modifiers": [],
    "mesh_bounding_boxes": {}
}

for obj in bpy.data.objects:
    # Basic info
    obj_info = {
        "name": obj.name,
        "type": obj.type,
        "location": [round(v, 4) for v in obj.location],
        "rotation_euler_deg": [round(math.degrees(v), 4) for v in obj.rotation_euler],
        "scale": [round(v, 4) for v in obj.scale]
    }
    result["objects"].append(obj_info)
    
    # Empty specific info
    if obj.type == 'EMPTY':
        result["empties"].append(obj_info)
    
    # Mesh specific info
    if obj.type == 'MESH':
        # Calculate bounding box dimensions (local space) to check elongation
        if obj.data and hasattr(obj.data, 'vertices') and len(obj.data.vertices) > 0:
            # We use local coordinates for shape analysis
            xs = [v.co.x for v in obj.data.vertices]
            ys = [v.co.y for v in obj.data.vertices]
            zs = [v.co.z for v in obj.data.vertices]
            if xs and ys and zs:
                dims = [max(xs)-min(xs), max(ys)-min(ys), max(zs)-min(zs)]
                # Sort dimensions to find aspect ratio independent of axis
                dims.sort() 
                result["mesh_bounding_boxes"][obj.name] = {
                    "dimensions_sorted": [round(d, 4) for d in dims],
                    "aspect_ratio": round(dims[2] / dims[1], 4) if dims[1] > 0.001 else 0
                }
        
        # Check modifiers
        for mod in obj.modifiers:
            if mod.type == 'ARRAY':
                mod_info = {
                    "object_name": obj.name,
                    "modifier_name": mod.name,
                    "count": mod.count,
                    "use_constant_offset": mod.use_constant_offset,
                    "use_relative_offset": mod.use_relative_offset,
                    "use_object_offset": mod.use_object_offset,
                    "offset_object_name": mod.offset_object.name if mod.offset_object else None,
                    "offset_object_type": mod.offset_object.type if mod.offset_object else None
                }
                result["array_modifiers"].append(mod_info)

print("RESULT_JSON:" + json.dumps(result))
ANALYSIS_EOF

SCENE_DATA="{}"
if [ "$FILE_VALID" = "true" ]; then
    # Run analysis script
    RAW_OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_fan.py -- "$OUTPUT_BLEND" 2>/dev/null || echo "")
    
    # Extract JSON from output
    for line in $RAW_OUTPUT; do
        if echo "$line" | grep -q "^RESULT_JSON:"; then
            SCENE_DATA=$(echo "$line" | sed 's/^RESULT_JSON://')
            break
        fi
    done
fi

# Create final JSON structure
python3 << PYEOF
import json

try:
    scene_data = json.loads('''$SCENE_DATA''')
except:
    scene_data = {}

result = {
    "file": {
        "exists": $FILE_EXISTS == "true" if "$FILE_EXISTS" == "true" else False,
        "size": $FILE_SIZE,
        "valid_blend": $FILE_VALID == "true" if "$FILE_VALID" == "true" else False,
        "created_during_task": $FILE_CREATED_DURING_TASK == "true" if "$FILE_CREATED_DURING_TASK" == "true" else False
    },
    "scene": scene_data,
    "screenshot_path": "/tmp/task_final.png"
}

with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to $RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "=== Export complete ==="