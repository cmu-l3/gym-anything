#!/bin/bash
echo "=== Exporting mesh cleanup results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
CLEANED_FILE="/home/ga/BlenderProjects/bmw_cleaned.blend"
RESULT_FILE="/tmp/task_result.json"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check basic file existence
EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$CLEANED_FILE" ]; then
    EXISTS="true"
    FILE_SIZE=$(stat -c%s "$CLEANED_FILE")
    MTIME=$(stat -c%Y "$CLEANED_FILE")
    if [ "$MTIME" -ge "$START_TIME" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 3. Analyze mesh topology using Blender (Headless)
# We define a python script to run inside Blender
cat > /tmp/analyze_mesh.py << 'PYEOF'
import bpy
import bmesh
import json
import sys
import os

result = {
    "mesh_found": False,
    "duplicates": 0,
    "loose_verts": 0,
    "degenerate_faces": 0,
    "inconsistent_normals": 0,
    "total_faces": 0,
    "total_verts": 0
}

try:
    # Open the cleaned file
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/bmw_cleaned.blend")
    
    # Find the main mesh
    target_obj = None
    max_verts = 0
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and len(obj.data.vertices) > max_verts:
            max_verts = len(obj.data.vertices)
            target_obj = obj
            
    if target_obj:
        result["mesh_found"] = True
        result["total_verts"] = len(target_obj.data.vertices)
        result["total_faces"] = len(target_obj.data.polygons)
        
        # Analyze using BMesh
        bpy.context.view_layer.objects.active = target_obj
        bpy.ops.object.mode_set(mode='EDIT')
        bm = bmesh.from_edit_mesh(target_obj.data)
        bm.verts.ensure_lookup_table()
        bm.faces.ensure_lookup_table()
        bm.edges.ensure_lookup_table()
        
        # 1. Count Loose Verts (no linked faces/edges)
        result["loose_verts"] = len([v for v in bm.verts if not v.link_edges])
        
        # 2. Count Duplicates (distance < 0.0001)
        # Using KDTree for efficiency
        from mathutils.kdtree import KDTree
        size = len(bm.verts)
        kd = KDTree(size)
        for i, v in enumerate(bm.verts):
            kd.insert(v.co, i)
        kd.balance()
        
        duplicates = 0
        seen = set()
        for i, v in enumerate(bm.verts):
            if i in seen: continue
            # Find close verts
            near = kd.find_range(v.co, 0.0001)
            if len(near) > 1:
                # Filter self
                others = [n for n in near if n[1] != i]
                if others:
                    duplicates += len(others)
                    for n in others:
                        seen.add(n[1])
        result["duplicates"] = duplicates
        
        # 3. Count Degenerate Faces (Area near zero)
        result["degenerate_faces"] = len([f for f in bm.faces if f.calc_area() < 1e-6])
        
        # 4. Check Normal Consistency
        # We simulate a "Recalculate Outside" on a copy and count changes
        # NOTE: This is complex to do perfectly, so we use a heuristic:
        # Check number of edges where adjacent faces point in same direction
        # (Winding order mismatch)
        bad_edges = 0
        total_interior_edges = 0
        
        for e in bm.edges:
            if len(e.link_faces) == 2:
                total_interior_edges += 1
                f1, f2 = e.link_faces
                
                # Get vertices of edge in order for f1
                v1, v2 = e.verts
                
                # Check winding in f1
                try:
                    i1 = f1.verts[:].index(v1)
                    v_next_f1 = f1.verts[(i1 + 1) % len(f1.verts)]
                except:
                    continue
                    
                is_f1_forward = (v_next_f1 == v2)
                
                # Check winding in f2
                try:
                    i2 = f2.verts[:].index(v1)
                    v_next_f2 = f2.verts[(i2 + 1) % len(f2.verts)]
                except:
                    continue
                    
                is_f2_forward = (v_next_f2 == v2)
                
                # If both winding orders are the same relative to the edge, 
                # one face is flipped relative to the other
                if is_f1_forward == is_f2_forward:
                    bad_edges += 1
                    
        result["inconsistent_normals"] = bad_edges
        result["total_interior_edges"] = total_interior_edges

except Exception as e:
    result["error"] = str(e)

print("JSON_START" + json.dumps(result) + "JSON_END")
PYEOF

# Run analysis
ANALYSIS_JSON="{}"
if [ "$EXISTS" = "true" ]; then
    OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_mesh.py 2>/dev/null)
    # Extract JSON between markers
    ANALYSIS_JSON=$(echo "$OUTPUT" | sed -n 's/.*JSON_START\(.*\)JSON_END.*/\1/p')
fi

# Combine all results
cat > "$RESULT_FILE" << EOF
{
    "file_exists": $EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": ${ANALYSIS_JSON:-{}}
}
EOF

# Copy stats for verifier
cp /tmp/initial_mesh_stats.json /tmp/initial_mesh_stats.json 2>/dev/null || echo "{}" > /tmp/initial_mesh_stats.json

# Set permissions
chmod 666 "$RESULT_FILE" /tmp/initial_mesh_stats.json 2>/dev/null

echo "Results exported to $RESULT_FILE"