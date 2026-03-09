#!/bin/bash
set -e
echo "=== Exporting Cloth Drape Simulation results ==="

PROJECTS_DIR="/home/ga/BlenderProjects"
BLEND_FILE="$PROJECTS_DIR/cloth_drape.blend"
RENDER_FILE="$PROJECTS_DIR/cloth_render.png"
RESULT_FILE="/tmp/task_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and basic properties
BLEND_EXISTS="false"
BLEND_SIZE=0
BLEND_VALID="false"
RENDER_EXISTS="false"
RENDER_SIZE=0

if [ -f "$BLEND_FILE" ]; then
    BLEND_EXISTS="true"
    BLEND_SIZE=$(stat -c%s "$BLEND_FILE" 2>/dev/null || echo "0")
    # Check BLENDER magic bytes
    MAGIC=$(head -c 7 "$BLEND_FILE" 2>/dev/null || echo "")
    if [ "$MAGIC" = "BLENDER" ]; then
        BLEND_VALID="true"
    fi
fi

if [ -f "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$RENDER_FILE" 2>/dev/null || echo "0")
fi

# Check render file timestamp vs task start
RENDER_AFTER_START="false"
if [ -f "$RENDER_FILE" ]; then
    RENDER_TIME=$(stat -c%Y "$RENDER_FILE" 2>/dev/null || echo "0")
    if [ "$RENDER_TIME" -gt "$TASK_START" ]; then
        RENDER_AFTER_START="true"
    fi
fi

# Analyze the blend file with Blender Python
# We need to verify physics modifiers and mesh deformation
cat > /tmp/analyze_cloth_scene.py << 'ANALYZE_EOF'
import bpy
import json
import sys
import math
import os

# Get filepath from args
blend_path = sys.argv[sys.argv.index("--") + 1]

try:
    bpy.ops.wm.open_mainfile(filepath=blend_path)
    
    result = {
        "cloth_objects": [],
        "collision_objects": [],
        "table_has_collision": False,
        "ground_has_collision": False,
        "cloth_vertex_count": 0,
        "cloth_z_variance": 0.0,
        "cloth_z_min": 0.0,
        "cloth_z_max": 0.0,
        "cloth_deformed": False,
        "frame_start": bpy.context.scene.frame_start,
        "frame_end": bpy.context.scene.frame_end,
        "frame_current": bpy.context.scene.frame_current,
        "total_objects": len(bpy.data.objects)
    }

    # Find cloth and collision objects
    for obj in bpy.data.objects:
        # Check modifiers
        has_cloth = False
        has_collision = False
        
        for mod in obj.modifiers:
            if mod.type == 'CLOTH':
                has_cloth = True
                
                # Analyze cloth mesh deformation
                # We need the evaluated mesh (after modifiers)
                depsgraph = bpy.context.evaluated_depsgraph_get()
                eval_obj = obj.evaluated_get(depsgraph)
                eval_mesh = eval_obj.to_mesh()
                
                vertex_count = len(eval_mesh.vertices)
                if vertex_count > 0:
                    z_coords = [v.co.z for v in eval_mesh.vertices]
                    z_min = min(z_coords)
                    z_max = max(z_coords)
                    z_mean = sum(z_coords) / vertex_count
                    z_variance = sum((z - z_mean)**2 for z in z_coords) / vertex_count
                    
                    cloth_info = {
                        "name": obj.name,
                        "vertex_count": vertex_count,
                        "z_variance": round(z_variance, 6),
                        "z_min": round(z_min, 4),
                        "z_max": round(z_max, 4)
                    }
                    result["cloth_objects"].append(cloth_info)
                    
                    # Update global max stats if this is the best cloth candidate
                    if vertex_count > result["cloth_vertex_count"]:
                        result["cloth_vertex_count"] = vertex_count
                        result["cloth_z_variance"] = round(z_variance, 6)
                        result["cloth_z_min"] = round(z_min, 4)
                        result["cloth_z_max"] = round(z_max, 4)
                        result["cloth_deformed"] = z_variance > 0.005 # Flat plane is 0
                
                eval_obj.to_mesh_clear()

            if mod.type == 'COLLISION':
                has_collision = True
                result["collision_objects"].append(obj.name)
                
                # Check specific objects
                name_lower = obj.name.lower()
                if "table" in name_lower:
                    result["table_has_collision"] = True
                if "ground" in name_lower or "floor" in name_lower:
                    result["ground_has_collision"] = True

    print("ANALYSIS_JSON:" + json.dumps(result))

except Exception as e:
    print(f"Error: {e}")
    # Output safe default
    print("ANALYSIS_JSON:" + json.dumps({"error": str(e)}))
ANALYZE_EOF

# Run analysis
ANALYSIS="{}"
if [ "$BLEND_VALID" = "true" ]; then
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_cloth_scene.py -- "$BLEND_FILE" 2>&1)
    ANALYSIS_LINE=$(echo "$ANALYSIS_OUTPUT" | grep "ANALYSIS_JSON:" | head -1)
    if [ -n "$ANALYSIS_LINE" ]; then
        ANALYSIS="${ANALYSIS_LINE#ANALYSIS_JSON:}"
    fi
fi

# Get render image dimensions if exists
RENDER_WIDTH=0
RENDER_HEIGHT=0
if [ "$RENDER_EXISTS" = "true" ]; then
    DIMS=$(python3 -c "
from PIL import Image
try:
    img = Image.open('$RENDER_FILE')
    print(f'{img.width} {img.height}')
except:
    print('0 0')
" 2>/dev/null || echo "0 0")
    RENDER_WIDTH=$(echo "$DIMS" | awk '{print $1}')
    RENDER_HEIGHT=$(echo "$DIMS" | awk '{print $2}')
fi

# Build final result JSON using Python for safety
python3 << PYEOF
import json
import os

try:
    analysis = json.loads('$ANALYSIS')
except:
    analysis = {}

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "blend_file": {
        "exists": $( [ "$BLEND_EXISTS" = "true" ] && echo "true" || echo "false" ),
        "size": $BLEND_SIZE,
        "valid": $( [ "$BLEND_VALID" = "true" ] && echo "true" || echo "false" )
    },
    "render_file": {
        "exists": $( [ "$RENDER_EXISTS" = "true" ] && echo "true" || echo "false" ),
        "size": $RENDER_SIZE,
        "width": $RENDER_WIDTH,
        "height": $RENDER_HEIGHT,
        "created_after_start": $( [ "$RENDER_AFTER_START" = "true" ] && echo "true" || echo "false" )
    },
    "scene_analysis": analysis,
    "screenshot_path": "/tmp/task_final.png",
    "render_path": "$RENDER_FILE"
}

# Write to temp file then move
with open("/tmp/task_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

mv /tmp/task_result_tmp.json "$RESULT_FILE"
chmod 666 "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="