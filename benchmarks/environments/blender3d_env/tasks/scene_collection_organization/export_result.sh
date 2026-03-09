#!/bin/bash
echo "=== Exporting Scene Collection Organization results ==="

source /workspace/scripts/task_utils.sh

BLEND_FILE="/home/ga/BlenderProjects/organized_scene.blend"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_MTIME="0"
FILE_VALID="false"
FILE_SIZE="0"

if [ -f "$BLEND_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$BLEND_FILE" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c%s "$BLEND_FILE" 2>/dev/null || echo "0")
    
    # Check magic bytes
    MAGIC=$(head -c 7 "$BLEND_FILE" 2>/dev/null | tr -d '\0')
    if [ "$MAGIC" = "BLENDER" ]; then
        FILE_VALID="true"
    fi
fi

# Check if file was modified/created during task
FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Analyze the blend file structure using Blender Python
SCENE_JSON="{}"
if [ "$FILE_VALID" = "true" ]; then
    echo "Analyzing scene structure..."
    cat > /tmp/analyze_scene.py << 'ANALYSIS_EOF'
import bpy
import json

# Open the file (passed via args in command line below)
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/organized_scene.blend")

data = {
    "total_objects": len(bpy.data.objects),
    "collections": {}
}

# Iterate through all collections
for col in bpy.data.collections:
    col_info = {
        "name": col.name,
        "hide_viewport": col.hide_viewport,
        "objects": []
    }
    
    for obj in col.objects:
        col_info["objects"].append({
            "name": obj.name,
            "type": obj.type
        })
    
    data["collections"][col.name] = col_info

# Identify orphans (objects in default/master collection only)
# Note: In Blender, objects can be in multiple collections.
# We want to check if the 'messy' configuration persists.
orphans = []
if "Collection" in bpy.data.collections:
    default_col = bpy.data.collections["Collection"]
    for obj in default_col.objects:
        orphans.append(obj.name)
data["orphans_in_default"] = orphans

print("JSON_START" + json.dumps(data) + "JSON_END")
ANALYSIS_EOF

    # Run analysis
    RAW_OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_scene.py 2>/dev/null)
    # Extract JSON between markers
    SCENE_JSON=$(echo "$RAW_OUTPUT" | grep -o "JSON_START.*JSON_END" | sed 's/JSON_START//;s/JSON_END//')
fi

# If extraction failed, default to empty object
if [ -z "$SCENE_JSON" ]; then
    SCENE_JSON="{}"
fi

# Construct final result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_valid": $FILE_VALID,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "scene_analysis": $SCENE_JSON
}
EOF

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="