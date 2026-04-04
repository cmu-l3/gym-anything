#!/bin/bash
echo "=== Exporting Volumetric Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_BLEND="/home/ga/BlenderProjects/volumetric_scene.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/volumetric_render.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check render file
RENDER_EXISTS="false"
RENDER_SIZE=0
RENDER_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$OUTPUT_RENDER")
    RENDER_MTIME=$(stat -c%Y "$OUTPUT_RENDER")
    if [ "$RENDER_MTIME" -ge "$TASK_START" ]; then
        RENDER_CREATED_DURING_TASK="true"
    fi
fi

# Check blend file
BLEND_EXISTS="false"
if [ -f "$OUTPUT_BLEND" ]; then
    BLEND_EXISTS="true"
fi

# Analyze the .blend file using Blender's Python API
# We need to detect: Spotlight, Volume Domain, World settings, Sun removal
echo "Analyzing scene file..."

ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_volumetric.XXXXXX.py)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import sys
import os

try:
    # Load the file
    filepath = "/home/ga/BlenderProjects/volumetric_scene.blend"
    if not os.path.exists(filepath):
        print("JSON:{\"error\": \"File not found\"}")
        sys.exit(0)
        
    bpy.ops.wm.open_mainfile(filepath=filepath)
    
    scene = bpy.context.scene
    
    # 1. Analyze Lights
    lights = []
    has_sun = False
    has_spot = False
    
    for obj in bpy.data.objects:
        if obj.type == 'LIGHT':
            l_data = obj.data
            light_info = {
                "name": obj.name,
                "type": l_data.type,
                "energy": l_data.energy,
                "visible": not obj.hide_render
            }
            lights.append(light_info)
            
            if l_data.type == 'SUN' and not obj.hide_render:
                has_sun = True
            if l_data.type == 'SPOT' and not obj.hide_render:
                has_spot = True

    # 2. Analyze Materials for Volumetrics
    has_volume_domain = False
    volume_density = 0.0
    
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            # Check active material
            if obj.active_material and obj.active_material.use_nodes:
                tree = obj.active_material.node_tree
                output_node = None
                
                # Find output node
                for node in tree.nodes:
                    if node.type == 'OUTPUT_MATERIAL':
                        output_node = node
                        break
                
                if output_node:
                    # Check what is connected to "Volume" input
                    vol_input = output_node.inputs.get('Volume')
                    if vol_input and vol_input.is_linked:
                        link = vol_input.links[0]
                        src_node = link.from_node
                        
                        # Is it a Volume shader?
                        if src_node.type in ['BSDF_PRINCIPLED_VOLUME', 'VOLUME_SCATTER', 'VOLUME_ABSORPTION']:
                            has_volume_domain = True
                            # Try to get density
                            if src_node.type == 'BSDF_PRINCIPLED_VOLUME':
                                density_socket = src_node.inputs.get('Density')
                                if density_socket:
                                    volume_density = density_socket.default_value
                            elif src_node.type == 'VOLUME_SCATTER':
                                density_socket = src_node.inputs.get('Density')
                                if density_socket:
                                    volume_density = density_socket.default_value
                            break

    # 3. Analyze World Background
    world_brightness = 1.0
    if scene.world and scene.world.use_nodes:
        tree = scene.world.node_tree
        bg_node = None
        for node in tree.nodes:
            if node.type == 'BACKGROUND':
                bg_node = node
                break
        
        if bg_node:
            color = bg_node.inputs['Color'].default_value
            strength = bg_node.inputs['Strength'].default_value
            # Perceived brightness
            luminance = (0.2126*color[0] + 0.7152*color[1] + 0.0722*color[2]) * strength
            world_brightness = luminance
    
    # 4. Render Settings
    render_engine = scene.render.engine

    result = {
        "valid_blend": True,
        "lights": lights,
        "has_sun": has_sun,
        "has_spot": has_spot,
        "has_volume_domain": has_volume_domain,
        "volume_density": volume_density,
        "world_brightness": world_brightness,
        "render_engine": render_engine
    }
    
    print("JSON:" + json.dumps(result))

except Exception as e:
    print("JSON:" + json.dumps({"error": str(e), "valid_blend": False}))
PYEOF

# Run analysis
ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
JSON_RESULT=$(echo "$ANALYSIS_OUTPUT" | grep '^JSON:' | sed 's/^JSON://')

# Fallback if python failed
if [ -z "$JSON_RESULT" ]; then
    JSON_RESULT='{"valid_blend": false, "error": "Analysis script failed to produce output"}'
fi

# Combine all results
FINAL_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$FINAL_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "render_exists": $RENDER_EXISTS,
    "render_size_bytes": $RENDER_SIZE,
    "render_created_during_task": $RENDER_CREATED_DURING_TASK,
    "blend_exists": $BLEND_EXISTS,
    "scene_analysis": $JSON_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$FINAL_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json