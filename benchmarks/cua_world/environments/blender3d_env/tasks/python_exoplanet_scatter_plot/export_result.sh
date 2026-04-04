#!/bin/bash
echo "=== Exporting Exoplanet Task Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_BLEND="/home/ga/BlenderProjects/exoplanet_viz.blend"
CSV_PATH="/home/ga/Desktop/exoplanets.csv"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output file exists
if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_BLEND")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_BLEND")
    
    # Check modification time
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_NEW="true"
    else
        FILE_NEW="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_NEW="false"
fi

# ================================================================
# INSPECT BLEND FILE
# ================================================================
# We use Blender's python to extract object data from the saved file
# and match it against the CSV data which we embed in the result.

SCENE_DATA="{\"error\": \"File not found\"}"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Inspecting Blender file..."
    
    # Create extraction script
    cat > /tmp/extract_scene.py << 'PYEOF'
import bpy
import json
import math

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/exoplanet_viz.blend")
    
    scene_objects = []
    
    # Check for collection
    coll_name = "StarCluster"
    collection_exists = coll_name in bpy.data.collections
    
    target_objects = []
    
    # If collection exists, get objects from it. Otherwise check all objects.
    if collection_exists:
        target_objects = bpy.data.collections[coll_name].objects
    else:
        target_objects = bpy.data.objects
        
    for obj in target_objects:
        # Get material color
        color = [0.8, 0.8, 0.8] # Default grey
        if obj.active_material:
            mat = obj.active_material
            if mat.use_nodes and mat.node_tree:
                # Try to find Principled BSDF
                bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
                if bsdf:
                    c = bsdf.inputs['Base Color'].default_value
                    color = [c[0], c[1], c[2]]
            else:
                # Viewport color
                c = mat.diffuse_color
                color = [c[0], c[1], c[2]]
                
        scene_objects.append({
            "name": obj.name,
            "type": obj.type,
            "location": [round(v, 3) for v in obj.location],
            "scale": [round(v, 3) for v in obj.scale],
            "color": [round(v, 3) for v in color]
        })

    result = {
        "collection_exists": collection_exists,
        "objects": scene_objects
    }
    
    print("JSON_START" + json.dumps(result) + "JSON_END")
    
except Exception as e:
    print(f"Error: {e}")
PYEOF

    # Run extraction
    EXTRACT_OUT=$(/opt/blender/blender --background --python /tmp/extract_scene.py 2>/dev/null)
    
    # Parse JSON from stdout
    SCENE_DATA=$(echo "$EXTRACT_OUT" | grep -o "JSON_START.*JSON_END" | sed 's/JSON_START//;s/JSON_END//')
    
    if [ -z "$SCENE_DATA" ]; then
        SCENE_DATA="{\"error\": \"Failed to parse blender output\"}"
    fi
fi

# ================================================================
# READ CSV DATA
# ================================================================
# We embed the CSV content into the JSON so the verifier has the ground truth
CSV_CONTENT="[]"
if [ -f "$CSV_PATH" ]; then
    CSV_CONTENT=$(python3 -c "import csv, json; print(json.dumps(list(csv.DictReader(open('$CSV_PATH')))))")
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_new": $FILE_NEW,
    "output_size": $OUTPUT_SIZE,
    "scene_data": $SCENE_DATA,
    "csv_data": $CSV_CONTENT
}
EOF

echo "Result exported to /tmp/task_result.json"