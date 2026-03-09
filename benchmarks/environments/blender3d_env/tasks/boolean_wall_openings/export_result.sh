#!/bin/bash
echo "=== Exporting boolean_wall_openings result ==="

source /workspace/scripts/task_utils.sh

# Configuration
OUTPUT_BLEND="/home/ga/BlenderProjects/wall_with_openings.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/wall_render.png"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check file existence
BLEND_EXISTS="false"
RENDER_EXISTS="false"
BLEND_SIZE="0"
RENDER_SIZE="0"
FILE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

if [ -f "$OUTPUT_BLEND" ]; then
    BLEND_EXISTS="true"
    BLEND_SIZE=$(stat -c%s "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    BLEND_MTIME=$(stat -c%Y "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    if [ "$BLEND_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$OUTPUT_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$OUTPUT_RENDER" 2>/dev/null || echo "0")
fi

# ================================================================
# ANALYZE SCENE WITH BLENDER PYTHON
# ================================================================
# We run this regardless of file modified time to prevent gaming via `touch`
# If the file doesn't exist, the python script will output default error JSON

ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_wall.XXXXXX.py)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import os
import sys

# Default result if load fails
result = {
    "wall_found": False,
    "face_count": 0,
    "unapplied_boolean_count": 0,
    "cutters_status": {},
    "valid_file": False
}

blend_path = "/home/ga/BlenderProjects/wall_with_openings.blend"

if os.path.exists(blend_path):
    try:
        bpy.ops.wm.open_mainfile(filepath=blend_path)
        result["valid_file"] = True
        
        # 1. Analyze Wall
        wall = bpy.data.objects.get("Wall")
        if wall and wall.type == 'MESH':
            result["wall_found"] = True
            result["face_count"] = len(wall.data.polygons)
            
            # Check for unapplied modifiers
            bool_mods = [m for m in wall.modifiers if m.type == 'BOOLEAN']
            result["unapplied_boolean_count"] = len(bool_mods)
            
        # 2. Analyze Cutters
        # "WindowCutter_Left", "WindowCutter_Right", "DoorCutter"
        target_cutters = ["WindowCutter_Left", "WindowCutter_Right", "DoorCutter"]
        for name in target_cutters:
            obj = bpy.data.objects.get(name)
            if obj:
                result["cutters_status"][name] = {
                    "exists": True,
                    "hide_viewport": obj.hide_viewport,
                    "hide_render": obj.hide_render
                }
            else:
                result["cutters_status"][name] = {
                    "exists": False
                }
                
    except Exception as e:
        result["error"] = str(e)

print("JSON_RESULT:" + json.dumps(result))
PYEOF

SCENE_INFO="{}"
if [ "$BLEND_EXISTS" = "true" ]; then
    PY_OUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    SCENE_INFO=$(echo "$PY_OUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://' || echo "{}")
fi
rm -f "$ANALYSIS_SCRIPT"

# Combine everything into final JSON
cat > /tmp/task_result.json << EOF
{
    "blend_exists": $BLEND_EXISTS,
    "blend_size": $BLEND_SIZE,
    "file_modified_during_task": $FILE_MODIFIED,
    "render_exists": $RENDER_EXISTS,
    "render_size": $RENDER_SIZE,
    "scene_analysis": $SCENE_INFO,
    "initial_face_count": $(cat /tmp/initial_state.json | grep initial_face_count | cut -d':' -f2 | tr -d '}' | tr -d ' ' || echo 6)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json