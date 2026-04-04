#!/bin/bash
echo "=== Exporting text_signage_metallic results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

BLEND_FILE="/home/ga/BlenderProjects/sign_scene.blend"
RENDER_FILE="/home/ga/BlenderProjects/sign_render.png"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check render file details
RENDER_EXISTS="false"
RENDER_SIZE_KB=0
RENDER_CREATED_DURING_TASK="false"

if [ -f "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE_BYTES=$(stat -c%s "$RENDER_FILE" 2>/dev/null || echo "0")
    RENDER_SIZE_KB=$((RENDER_SIZE_BYTES / 1024))
    RENDER_MTIME=$(stat -c%Y "$RENDER_FILE" 2>/dev/null || echo "0")
    
    if [ "$RENDER_MTIME" -ge "$TASK_START" ]; then
        RENDER_CREATED_DURING_TASK="true"
    fi
fi

# Check blend file existence
BLEND_EXISTS="false"
if [ -f "$BLEND_FILE" ]; then
    BLEND_EXISTS="true"
fi

# Analyze the .blend file using Blender's Python API
# We create a script to inspect the scene content (text objects, materials)
cat > /tmp/analyze_signage.py << 'PYEOF'
import bpy
import json
import sys

output_path = sys.argv[sys.argv.index("--") + 1]

try:
    bpy.ops.wm.open_mainfile(filepath=output_path)
    
    scene_data = {
        "text_objects": [],
        "base_cube_exists": False,
        "object_count": len(bpy.data.objects)
    }

    # Check for BaseCube (should be deleted)
    if "BaseCube" in bpy.data.objects:
        scene_data["base_cube_exists"] = True

    # Find all text objects
    for obj in bpy.data.objects:
        if obj.type == 'FONT':
            text_info = {
                "name": obj.name,
                "body": obj.data.body,
                "extrude": obj.data.extrude,
                "bevel_depth": obj.data.bevel_depth,
                "bevel_resolution": obj.data.bevel_resolution,
                "location": list(obj.location),
                "materials": []
            }
            
            # Check materials on this object
            for slot in obj.material_slots:
                if slot.material and slot.material.use_nodes:
                    mat = slot.material
                    mat_info = {"name": mat.name}
                    
                    # Find Principled BSDF
                    bsdf = None
                    for node in mat.node_tree.nodes:
                        if node.type == 'BSDF_PRINCIPLED':
                            bsdf = node
                            break
                    
                    if bsdf:
                        # Get Base Color
                        bc = bsdf.inputs['Base Color'].default_value
                        mat_info['base_color'] = [bc[0], bc[1], bc[2], bc[3]]
                        
                        # Get Metallic
                        mat_info['metallic'] = bsdf.inputs['Metallic'].default_value
                        
                        # Get Roughness
                        mat_info['roughness'] = bsdf.inputs['Roughness'].default_value
                    
                    text_info['materials'].append(mat_info)
            
            scene_data['text_objects'].append(text_info)

    print("JSON_RESULT:" + json.dumps(scene_data))

except Exception as e:
    print("JSON_RESULT:" + json.dumps({"error": str(e)}))
PYEOF

# Run analysis if blend file exists
SCENE_DATA="{}"
if [ "$BLEND_EXISTS" = "true" ]; then
    # Run blender headless
    ANALYSIS_OUT=$(/opt/blender/blender --background --python /tmp/analyze_signage.py -- "$BLEND_FILE" 2>/dev/null)
    # Extract JSON from stdout
    SCENE_DATA=$(echo "$ANALYSIS_OUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
fi

# If extraction failed or file didn't exist, default to empty dict
if [ -z "$SCENE_DATA" ]; then
    SCENE_DATA='{"error": "Could not analyze file"}'
fi

# Combine everything into final result JSON
cat > /tmp/task_result.json << EOF
{
    "render_exists": $RENDER_EXISTS,
    "render_size_kb": $RENDER_SIZE_KB,
    "render_created_during_task": $RENDER_CREATED_DURING_TASK,
    "blend_exists": $BLEND_EXISTS,
    "scene_analysis": $SCENE_DATA,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="