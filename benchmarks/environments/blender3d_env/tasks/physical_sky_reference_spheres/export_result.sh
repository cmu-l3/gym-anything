#!/bin/bash
echo "=== Exporting physical_sky_reference_spheres result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File paths
BLEND_FILE="/home/ga/BlenderProjects/sky_reference_setup.blend"
RENDER_FILE="/home/ga/BlenderProjects/sky_reference_render.png"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check render output
RENDER_EXISTS="false"
RENDER_WIDTH=0
RENDER_HEIGHT=0
RENDER_SIZE_KB=0
if [ -f "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE_KB=$(du -k "$RENDER_FILE" | cut -f1)
    
    # Get dimensions using python
    DIMENSIONS=$(python3 -c "
try:
    from PIL import Image
    with Image.open('$RENDER_FILE') as img:
        print(f'{img.width} {img.height}')
except:
    print('0 0')
")
    RENDER_WIDTH=$(echo $DIMENSIONS | cut -d' ' -f1)
    RENDER_HEIGHT=$(echo $DIMENSIONS | cut -d' ' -f2)
fi

# Check Blend file and analyze scene
BLEND_EXISTS="false"
SCENE_DATA="{}"

if [ -f "$BLEND_FILE" ]; then
    BLEND_EXISTS="true"
    
    # Analyze the scene using Blender's Python API
    # We use a temp script to extract specific data about World and Objects
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_sky.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/sky_reference_setup.blend")
    
    data = {
        "world": {"has_sky": False, "sky_type": None, "sun_elevation": None},
        "objects": []
    }

    # Analyze World
    world = bpy.context.scene.world
    if world and world.use_nodes:
        for node in world.node_tree.nodes:
            if node.type == 'TEX_ENVIRONMENT' or node.type == 'TEX_SKY':
                data["world"]["has_sky"] = True
                if node.type == 'TEX_SKY':
                    data["world"]["sky_type"] = node.sky_type # NISHITA, HOSEK_WILKIE, etc.
                    if node.sky_type == 'NISHITA':
                        data["world"]["sun_elevation"] = node.sun_elevation # radians

    # Analyze Objects (looking for spheres)
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            # Check materials
            mats = []
            for slot in obj.material_slots:
                if slot.material and slot.material.use_nodes:
                    mat_data = {"name": slot.material.name, "metallic": -1, "roughness": -1, "base_color": [0,0,0]}
                    # Find Principled BSDF
                    for node in slot.material.node_tree.nodes:
                        if node.type == 'BSDF_PRINCIPLED':
                            # Get values (handling default values vs inputs)
                            # Metallic
                            if not node.inputs['Metallic'].is_linked:
                                mat_data["metallic"] = node.inputs['Metallic'].default_value
                            # Roughness
                            if not node.inputs['Roughness'].is_linked:
                                mat_data["roughness"] = node.inputs['Roughness'].default_value
                            # Base Color
                            if not node.inputs['Base Color'].is_linked:
                                c = node.inputs['Base Color'].default_value
                                mat_data["base_color"] = [c[0], c[1], c[2]]
                            break
                    mats.append(mat_data)
            
            data["objects"].append({
                "name": obj.name,
                "location": [obj.location.x, obj.location.y, obj.location.z],
                "materials": mats
            })

    print("JSON_START" + json.dumps(data) + "JSON_END")

except Exception as e:
    print(f"Error: {e}")
PYEOF

    # Run analysis
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    
    # Extract JSON
    SCENE_DATA=$(echo "$ANALYSIS_OUTPUT" | grep -o "JSON_START.*JSON_END" | sed 's/JSON_START//;s/JSON_END//')
    if [ -z "$SCENE_DATA" ]; then SCENE_DATA="{}"; fi
    
    rm -f "$ANALYSIS_SCRIPT"
fi

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "blend_exists": $BLEND_EXISTS,
    "render_exists": $RENDER_EXISTS,
    "render_width": $RENDER_WIDTH,
    "render_height": $RENDER_HEIGHT,
    "render_size_kb": $RENDER_SIZE_KB,
    "scene_analysis": $SCENE_DATA
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="