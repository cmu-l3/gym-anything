#!/bin/bash
echo "=== Exporting Desk Lamp Armature Rig results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

BLEND_FILE="/home/ga/BlenderProjects/lamp_rigged.blend"
RESULT_FILE="/tmp/task_result.json"

# Check file existence
if [ -f "$BLEND_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$BLEND_FILE")
    FILE_MTIME=$(stat -c%Y "$BLEND_FILE")
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
fi

# Create analysis script
cat > /tmp/analyze_rig.py << 'PYEOF'
import bpy
import json
import sys

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/lamp_rigged.blend")
except:
    print(json.dumps({"error": "Failed to open blend file"}))
    sys.exit(0)

result = {
    "armatures": [],
    "meshes": {}
}

# Find all armatures
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE':
        arm_data = {
            "name": obj.name,
            "bones": []
        }
        for bone in obj.data.bones:
            arm_data["bones"].append({
                "name": bone.name,
                "parent": bone.parent.name if bone.parent else None,
                "head": list(bone.head_local),
                "tail": list(bone.tail_local),
                "length": bone.length
            })
        result["armatures"].append(arm_data)

# Check specific lamp meshes
target_meshes = ["LampBase", "LampLowerArm", "LampUpperArm", "LampHead"]
for mesh_name in target_meshes:
    obj = bpy.data.objects.get(mesh_name)
    if obj:
        mesh_info = {
            "exists": True,
            "parent": obj.parent.name if obj.parent else None,
            "parent_type": obj.parent.type if obj.parent else None,
            "parent_bone": obj.parent_bone,
            "modifiers": [m.type for m in obj.modifiers]
        }
        result["meshes"][mesh_name] = mesh_info
    else:
        result["meshes"][mesh_name] = {"exists": False}

print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run analysis
ANALYSIS_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Analyzing blend file..."
    OUTPUT=$(su - ga -c "/opt/blender/blender --background --python /tmp/analyze_rig.py" 2>/dev/null)
    # Extract JSON line
    ANALYSIS_JSON=$(echo "$OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
fi

# Combine into final result
cat > /tmp/final_result_gen.py << PYEOF
import json
import time

try:
    analysis = json.loads('''$ANALYSIS_JSON''')
except:
    analysis = {}

final = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": "$FILE_EXISTS" == "true",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "analysis": analysis
}

print(json.dumps(final))
PYEOF

python3 /tmp/final_result_gen.py > "$RESULT_FILE"

# Cleanup
rm -f /tmp/analyze_rig.py /tmp/final_result_gen.py /tmp/create_lamp_scene.py

echo "Result saved to $RESULT_FILE"