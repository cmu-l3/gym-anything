#!/bin/bash
echo "=== Exporting print_ready_stl_export result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_STL="/home/ga/BlenderProjects/suzanne_print.stl"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 1. Check File Existence and Metadata
if [ -f "$OUTPUT_STL" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_STL" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_STL" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 2. Analyze STL Geometry using Blender Python
# We launch a background Blender instance to import the STL and measure it.
# This confirms the actual geometry in the file, regardless of how the agent set up the scene units.
echo "Analyzing STL geometry..."

ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_stl.XXXXXX.py)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import mathutils
import os
import sys

# Clear default scene
bpy.ops.wm.read_homefile(use_empty=True)

stl_path = "/home/ga/BlenderProjects/suzanne_print.stl"
result = {
    "valid_geometry": False,
    "dimensions": [0, 0, 0],
    "vertex_count": 0,
    "object_count": 0,
    "error": None
}

try:
    if os.path.exists(stl_path):
        # Import STL
        # In Blender 4.x, stl import might be via bpy.ops.wm.stl_import or import_mesh.stl
        # We try the standard operator. 'global_scale=1.0' preserves units in file.
        try:
            bpy.ops.import_mesh.stl(filepath=stl_path, global_scale=1.0)
        except AttributeError:
            # Fallback for newer Blender versions if API changed
            bpy.ops.wm.stl_import(filepath=stl_path)

        # Get imported objects
        imported_objs = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
        result["object_count"] = len(imported_objs)

        if imported_objs:
            # Join them to get total bounding box if multiple parts (though task asks for union)
            ctx = bpy.context.copy()
            ctx['active_object'] = imported_objs[0]
            ctx['selected_editable_objects'] = imported_objs
            
            if len(imported_objs) > 1:
                bpy.ops.object.join(ctx)
            
            obj = bpy.context.scene.objects[0]
            result["vertex_count"] = len(obj.data.vertices)
            result["valid_geometry"] = True
            
            # Calculate dimensions
            # Dimensions in Blender are axis aligned bounding box
            result["dimensions"] = [
                round(obj.dimensions.x, 3),
                round(obj.dimensions.y, 3),
                round(obj.dimensions.z, 3)
            ]
            
            # Calculate bounds center to check positioning (optional)
            result["location"] = [
                round(obj.location.x, 3),
                round(obj.location.y, 3),
                round(obj.location.z, 3)
            ]
            
    else:
        result["error"] = "File not found"

except Exception as e:
    result["error"] = str(e)

print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run analysis
ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
GEOMETRY_JSON=$(echo "$ANALYSIS_OUTPUT" | grep '^JSON_RESULT:' | sed 's/^JSON_RESULT://')

if [ -z "$GEOMETRY_JSON" ]; then
    GEOMETRY_JSON='{"error": "Failed to parse Blender output"}'
fi

rm -f "$ANALYSIS_SCRIPT"

# 3. Compile Final JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "geometry": $GEOMETRY_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Export completed. Result:"
cat /tmp/task_result.json