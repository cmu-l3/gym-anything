#!/bin/bash
echo "=== Exporting lattice_deformation_setup result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_BLEND="/home/ga/BlenderProjects/lattice_warp.blend"

# Check if output file exists
if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    # Check magic bytes
    MAGIC=$(head -c 7 "$OUTPUT_BLEND" 2>/dev/null | tr -d '\0')
    if [ "$MAGIC" = "BLENDER" ]; then
        IS_VALID_BLEND="true"
    else
        IS_VALID_BLEND="false"
    fi
else
    OUTPUT_EXISTS="false"
    IS_VALID_BLEND="false"
fi

# Analyze the scene using Blender Python
# We need to verify:
# 1. Text object "GALAXY" exists and has Extrude > 0
# 2. Lattice object exists
# 3. Text object has Lattice Modifier pointing to Lattice
# 4. Lattice points are NOT in default positions (deformation applied)

SCENE_ANALYSIS='{"error": "Analysis failed"}'

if [ "$IS_VALID_BLEND" = "true" ]; then
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_lattice.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math
import mathutils

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/lattice_warp.blend")

result = {
    "text_found": False,
    "text_content": "",
    "text_extruded": False,
    "lattice_found": False,
    "lattice_resolution": [0, 0, 0],
    "modifier_correct": False,
    "deformation_score": 0.0,
    "text_object_name": "",
    "lattice_object_name": ""
}

# 1. Find Text Object
text_objs = [o for o in bpy.data.objects if o.type == 'FONT']
target_text = None
for t in text_objs:
    if t.data.body == "GALAXY":
        target_text = t
        result["text_found"] = True
        result["text_content"] = t.data.body
        result["text_object_name"] = t.name
        if t.data.extrude > 0.0:
            result["text_extruded"] = True
        break

# If specific "GALAXY" not found, take the first text object for partial credit/analysis
if not target_text and text_objs:
    target_text = text_objs[0]
    result["text_content"] = target_text.data.body
    result["text_object_name"] = target_text.name
    if target_text.data.extrude > 0.0:
        result["text_extruded"] = True

# 2. Find Lattice Object
lattice_objs = [o for o in bpy.data.objects if o.type == 'LATTICE']
target_lattice = None
if lattice_objs:
    target_lattice = lattice_objs[0]
    result["lattice_found"] = True
    result["lattice_object_name"] = target_lattice.name
    data = target_lattice.data
    result["lattice_resolution"] = [data.points_u, data.points_v, data.points_w]

# 3. Check Modifier
if target_text and target_lattice:
    for mod in target_text.modifiers:
        if mod.type == 'LATTICE' and mod.object == target_lattice:
            result["modifier_correct"] = True
            break

# 4. Calculate Deformation (Anti-Gaming)
# Create a temporary default lattice with same resolution to compare points
if target_lattice:
    data = target_lattice.data
    
    # Calculate expected points for a default regular grid
    # Lattice points are usually in range -0.5 to 0.5 in object space
    # But calculating exact default positions for arbitrary resolution can be tricky.
    # Alternative: Check if points are collinear/coplanar in a grid pattern?
    # Simpler: Create a temp lattice
    
    temp_lattice_data = bpy.data.lattices.new("TempLattice")
    temp_lattice_data.points_u = data.points_u
    temp_lattice_data.points_v = data.points_v
    temp_lattice_data.points_w = data.points_w
    
    # Compare points
    total_diff = 0.0
    try:
        # Check first 50 points to save time if resolution is huge
        count = min(len(data.points), len(temp_lattice_data.points))
        for i in range(count):
            p1 = data.points[i].co_deform
            p2 = temp_lattice_data.points[i].co_deform
            diff = (p1 - p2).length
            total_diff += diff
    except Exception as e:
        print(f"Error comparing points: {e}")
        
    result["deformation_score"] = round(total_diff, 4)
    
    # Cleanup
    bpy.data.lattices.remove(temp_lattice_data)

print("JSON_RESULT:" + json.dumps(result))
PYEOF

    # Run analysis
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    SCENE_ANALYSIS=$(echo "$ANALYSIS_OUTPUT" | grep '^JSON_RESULT:' | sed 's/^JSON_RESULT://')
    
    if [ -z "$SCENE_ANALYSIS" ]; then
        SCENE_ANALYSIS='{"error": "Could not parse Blender output"}'
    fi
    
    rm -f "$ANALYSIS_SCRIPT"
fi

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "is_valid_blend": $IS_VALID_BLEND,
    "scene_analysis": $SCENE_ANALYSIS,
    "task_timestamp": $(date +%s)
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json