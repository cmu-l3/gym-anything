#!/bin/bash
echo "=== Exporting Shape Key Morphing Animation results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BLEND_FILE="/home/ga/BlenderProjects/morph_animation.blend"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if file exists
if [ ! -f "$BLEND_FILE" ]; then
    echo "Output blend file not found: $BLEND_FILE"
    echo '{"file_exists": false, "error": "File not found"}' > "$RESULT_FILE"
    chmod 666 "$RESULT_FILE"
    exit 0
fi

# Check timestamps
FILE_MTIME=$(stat -c%Y "$BLEND_FILE" 2>/dev/null || echo "0")
FILE_MODIFIED_DURING_TASK="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED_DURING_TASK="true"
fi

FILE_SIZE_KB=$(du -k "$BLEND_FILE" | cut -f1)

# Analyze blend file contents with Blender Python
echo "Analyzing blend file structure..."
cat > /tmp/analyze_morph.py << 'PYEOF'
import bpy
import json
import math
import sys

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/morph_animation.blend")
    
    result = {
        "morph_cube_found": False,
        "shape_key_count": 0,
        "shape_key_names": [],
        "vertex_displacements": {},
        "displacement_similarity": 1.0,
        "has_animation_data": False,
        "fcurve_count": 0,
        "fcurve_details": [],
        "frame_start": bpy.context.scene.frame_start,
        "frame_end": bpy.context.scene.frame_end,
        "errors": []
    }

    # Find MorphCube
    morph_cube = bpy.data.objects.get("MorphCube")
    if not morph_cube:
        # Fallback search
        for obj in bpy.data.objects:
            if obj.type == 'MESH' and "morph" in obj.name.lower():
                morph_cube = obj
                break
    
    if morph_cube:
        result["morph_cube_found"] = True
        
        # Check Shape Keys
        if morph_cube.data.shape_keys:
            key_blocks = morph_cube.data.shape_keys.key_blocks
            result["shape_key_count"] = len(key_blocks)
            result["shape_key_names"] = [kb.name for kb in key_blocks]
            
            # Calculate displacements relative to Basis (first key)
            if len(key_blocks) > 0:
                basis = key_blocks[0]
                basis_verts = [v.co.copy() for v in basis.data]
                n_verts = len(basis_verts)
                
                disp_vectors = {}
                
                for i, kb in enumerate(key_blocks):
                    if i == 0: continue # Skip Basis
                    
                    kb_verts = [v.co.copy() for v in kb.data]
                    total_disp = 0.0
                    displacements = []
                    
                    for v_idx in range(min(n_verts, len(kb_verts))):
                        # Euclidean distance
                        diff = (kb_verts[v_idx] - basis_verts[v_idx]).length
                        displacements.append(diff)
                        total_disp += diff
                    
                    avg_disp = total_disp / max(1, n_verts)
                    max_disp = max(displacements) if displacements else 0
                    nonzero = sum(1 for d in displacements if d > 0.001)
                    
                    result["vertex_displacements"][kb.name] = {
                        "avg": round(avg_disp, 4),
                        "max": round(max_disp, 4),
                        "nonzero_count": nonzero
                    }
                    disp_vectors[kb.name] = displacements

                # Check if keys are distinct (simple cosine similarity check on displacement magnitudes)
                if len(disp_vectors) >= 2:
                    keys = list(disp_vectors.keys())
                    v1 = disp_vectors[keys[0]]
                    v2 = disp_vectors[keys[1]]
                    # Treat as vectors
                    dot = sum(a*b for a,b in zip(v1,v2))
                    mag1 = math.sqrt(sum(a*a for a in v1))
                    mag2 = math.sqrt(sum(b*b for b in v2))
                    if mag1 > 0 and mag2 > 0:
                        result["displacement_similarity"] = round(dot / (mag1 * mag2), 4)
                    else:
                        result["displacement_similarity"] = 0.0

        # Check Animation Data
        if morph_cube.data.shape_keys and morph_cube.data.shape_keys.animation_data:
            anim = morph_cube.data.shape_keys.animation_data
            if anim.action:
                result["has_animation_data"] = True
                result["fcurve_count"] = len(anim.action.fcurves)
                
                for fc in anim.action.fcurves:
                    pts = []
                    for kp in fc.keyframe_points:
                        pts.append({"frame": kp.co[0], "value": kp.co[1]})
                    
                    result["fcurve_details"].append({
                        "data_path": fc.data_path,
                        "point_count": len(pts),
                        "points": pts
                    })

    print("JSON_RESULT:" + json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

# Run analysis
ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_morph.py 2>&1)
JSON_CONTENT=$(echo "$ANALYSIS_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')

if [ -z "$JSON_CONTENT" ]; then
    JSON_CONTENT='{"error": "Failed to parse Blender output"}'
fi

# Combine results
cat > "$RESULT_FILE" << EOF
{
    "file_exists": true,
    "file_size_kb": $FILE_SIZE_KB,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "analysis": $JSON_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "Result exported to $RESULT_FILE"