#!/bin/bash
echo "=== Exporting Geometry Nodes Fence result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_BLEND="/home/ga/BlenderProjects/procedural_fence.blend"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Basic file checks
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# ================================================================
# ADVANCED SCENE ANALYSIS (HEADLESS BLENDER)
# ================================================================
# This script loads the user's file and performs "stress tests"
# to verify the procedural nature of the solution.

ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_fence.XXXXXX.py)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math
import sys

# Results dictionary
result = {
    "valid_blend": True,
    "modifier_found": False,
    "resampling_correct": False,
    "instancing_correct": False,
    "alignment_correct": False,
    "procedural_check_passed": False,
    "instance_count": 0,
    "errors": []
}

try:
    # Load the user's file
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/procedural_fence.blend")
    
    # Get objects
    path = bpy.data.objects.get("FencePath")
    post = bpy.data.objects.get("FencePost")
    
    if not path:
        result["errors"].append("FencePath object not found")
    else:
        # 1. CHECK MODIFIER
        geo_mod = next((m for m in path.modifiers if m.type == 'NODES'), None)
        if geo_mod:
            result["modifier_found"] = True
            
            # 2. CHECK INSTANCING (Initial State)
            # Evaluate the dependency graph to see generated geometry
            depsgraph = bpy.context.evaluated_depsgraph_get()
            eval_path = path.evaluated_get(depsgraph)
            
            # Count instances
            instances = [i for i in depsgraph.object_instances if i.parent == eval_path]
            instance_count = len(instances)
            result["instance_count"] = instance_count
            
            # Estimated length of curve (approx 20m from setup script)
            # 20m / 1.5m spacing ~= 13-14 posts
            if 10 <= instance_count <= 20:
                result["resampling_correct"] = True
            
            if instance_count > 0:
                # Check what is being instanced
                if instances[0].object.name == "FencePost" or (post and instances[0].object.data == post.data):
                    result["instancing_correct"] = True

                # 3. CHECK ALIGNMENT
                # Collect rotations of all instances
                rotations = set()
                for i in instances:
                    # Round rotation to detect variation
                    rot = tuple(round(x, 2) for x in i.matrix_world.to_euler())
                    rotations.add(rot)
                
                # If curve is S-shaped, tangent changes, so rotations MUST vary
                # If all rotations are identical, they didn't align to vector
                if len(rotations) > 3:
                    result["alignment_correct"] = True
            
            # 4. PROCEDURAL STRESS TEST (Anti-Gaming)
            # We will extend the curve and check if count increases automatically
            initial_count = instance_count
            
            # Modify the curve geometry in the original object (not evaluated)
            bpy.context.view_layer.objects.active = path
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.curve.select_all(action='SELECT')
            # Translate all points to stretch it significantly (doubling length roughly)
            bpy.ops.transform.translate(value=(20, 0, 0))
            bpy.ops.object.mode_set(mode='OBJECT')
            
            # Re-evaluate
            depsgraph_new = bpy.context.evaluated_depsgraph_get()
            eval_path_new = path.evaluated_get(depsgraph_new)
            new_instances = [i for i in depsgraph_new.object_instances if i.parent == eval_path_new]
            new_count = len(new_instances)
            
            result["stress_test_initial"] = initial_count
            result["stress_test_final"] = new_count
            
            # If the setup is procedural, count should increase significantly
            if new_count > initial_count + 5:
                result["procedural_check_passed"] = True

except Exception as e:
    result["errors"].append(str(e))
    result["valid_blend"] = False

print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run analysis
if [ "$OUTPUT_EXISTS" = "true" ]; then
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    JSON_LINE=$(echo "$ANALYSIS_OUTPUT" | grep "JSON_RESULT:" | head -1)
    ANALYSIS_JSON="${JSON_LINE#JSON_RESULT:}"
else
    ANALYSIS_JSON="{}"
fi

rm -f "$ANALYSIS_SCRIPT"

# Combine into final result
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "analysis": ${ANALYSIS_JSON:-null}
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json