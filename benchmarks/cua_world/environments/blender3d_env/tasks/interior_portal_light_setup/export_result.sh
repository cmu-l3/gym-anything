#!/bin/bash
echo "=== Exporting Interior Portal Light task results ==="

# Directories and Files
OUTPUT_FILE="/home/ga/BlenderProjects/portal_setup.blend"
RESULT_JSON="/tmp/task_result.json"
TASK_START_FILE="/tmp/task_start_time.txt"

# Default values
EXISTS=false
MODIFIED=false
LIGHT_FOUND=false
IS_PORTAL=false
POSITION_SCORE=0
SIZE_SCORE=0
ALIGNMENT_SCORE=0

# Check timestamps
START_TIME=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
if [ -f "$OUTPUT_FILE" ]; then
    EXISTS=true
    FILE_TIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_TIME" -ge "$START_TIME" ]; then
        MODIFIED=true
    fi
fi

# Analyze the blend file using Blender Python
if [ "$EXISTS" = "true" ]; then
    echo "Analyzing scene..."
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_portal.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math
import mathutils

# Open the file
try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/portal_setup.blend")
except:
    pass

# Target definitions (Window)
# Window center: (0, 2, 1.5)
# Window normal: (0, -1, 0) [Pointing IN to the room]
# Window size: 2.0 (width), 1.5 (height)
TARGET_LOC = mathutils.Vector((0.0, 2.0, 1.5))
TARGET_NORMAL = mathutils.Vector((0.0, -1.0, 0.0))
TARGET_SIZE_X = 2.0
TARGET_SIZE_Y = 1.5

best_light = None
best_score = -1.0

result = {
    "light_found": False,
    "lights_data": []
}

for obj in bpy.data.objects:
    if obj.type == 'LIGHT' and obj.data.type == 'AREA':
        light = obj.data
        
        # Calculate scores
        
        # 1. Location Distance
        dist = (obj.location - TARGET_LOC).length
        
        # 2. Alignment (Dot product of light direction vs target normal)
        # Area light default points down -Z. We need to apply object rotation.
        # Local -Z axis in World Space:
        light_direction = obj.matrix_world.to_3x3() @ mathutils.Vector((0, 0, -1))
        light_direction.normalize()
        alignment = light_direction.dot(TARGET_NORMAL)
        
        # 3. Portal Property
        is_portal = getattr(light.cycles, "is_portal", False)
        
        # 4. Size (Area match)
        # Area light size: size (X), size_y (Y) (if rectangle)
        # Note: If shape is SQUARE, size_y might not be used or equals size
        sx = light.size
        sy = light.size_y if light.shape == 'RECTANGLE' else light.size
        
        # We try to match dimensions. 2x1.5. 
        # Orientation matters for size (X vs Y), but let's just check if dimensions match the set {2.0, 1.5}
        dims = sorted([sx, sy])
        targets = sorted([TARGET_SIZE_X, TARGET_SIZE_Y])
        
        size_diff = abs(dims[0] - targets[0]) + abs(dims[1] - targets[1])
        
        light_data = {
            "name": obj.name,
            "location": list(obj.location),
            "distance": dist,
            "alignment": alignment,
            "is_portal": is_portal,
            "size": [sx, sy],
            "shape": light.shape,
            "size_diff": size_diff
        }
        result["lights_data"].append(light_data)
        
        # Heuristic to find the "intended" portal light
        # Prefer Portal=True, then closest distance
        score = (1000 if is_portal else 0) - dist
        
        if score > best_score:
            best_score = score
            best_light = light_data

if best_light:
    result["light_found"] = True
    result["best_light"] = best_light

print("JSON_RESULT:" + json.dumps(result))
PYEOF

    # Run analysis
    ANALYSIS_OUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    JSON_STR=$(echo "$ANALYSIS_OUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
    
    if [ -n "$JSON_STR" ]; then
        echo "$JSON_STR" > /tmp/scene_analysis.json
    else
        echo '{"light_found": false}' > /tmp/scene_analysis.json
    fi
    rm -f "$ANALYSIS_SCRIPT"
else
    echo '{"light_found": false}' > /tmp/scene_analysis.json
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct final JSON
cat > "$RESULT_JSON" << EOF
{
    "output_exists": $EXISTS,
    "output_modified": $MODIFIED,
    "analysis": $(cat /tmp/scene_analysis.json),
    "task_start_timestamp": $START_TIME
}
EOF

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"