#!/bin/bash
echo "=== Exporting PBR Assembly Result ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Paths
OUTPUT_BLEND="/home/ga/BlenderProjects/pbr_material_complete.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/pbr_render.png"

# Check file existence
BLEND_EXISTS="false"
RENDER_EXISTS="false"
RENDER_SIZE="0"

if [ -f "$OUTPUT_BLEND" ]; then BLEND_EXISTS="true"; fi
if [ -f "$OUTPUT_RENDER" ]; then 
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$OUTPUT_RENDER" 2>/dev/null || echo "0")
fi

# ================================================================
# ANALYZE BLENDER NODE GRAPH
# ================================================================
# We use a python script to inspect the internal state of the material
# This is much more reliable than VLM for checking "Non-Color" settings

ANALYSIS_SCRIPT="/tmp/analyze_pbr.py"
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import os

result = {
    "material_found": False,
    "nodes": [],
    "connections": [],
    "textures": {},
    "color_spaces": {},
    "error": None
}

try:
    # Open the file
    filepath = "/home/ga/BlenderProjects/pbr_material_complete.blend"
    if not os.path.exists(filepath):
        result["error"] = "File not found"
    else:
        bpy.ops.wm.open_mainfile(filepath=filepath)
        
        # Find object and material
        obj = bpy.data.objects.get("GroundPlane")
        if obj and obj.active_material:
            mat = obj.active_material
            result["material_found"] = True
            result["material_name"] = mat.name
            
            if mat.use_nodes and mat.node_tree:
                tree = mat.node_tree
                
                # List all nodes
                for node in tree.nodes:
                    node_data = {
                        "name": node.name,
                        "type": node.type,
                        "label": node.label
                    }
                    
                    # If texture, get image name and color space
                    if node.type == 'TEX_IMAGE':
                        if node.image:
                            node_data["image"] = node.image.name
                            # Blender 4.0+ uses colorspace_settings on image_user or image
                            # Checking colorspace setting
                            try:
                                node_data["colorspace"] = node.image.colorspace_settings.name
                            except:
                                node_data["colorspace"] = "Unknown"
                        else:
                            node_data["image"] = None
                            
                    result["nodes"].append(node_data)
                
                # Trace inputs of Principled BSDF
                bsdf = None
                for node in tree.nodes:
                    if node.type == 'BSDF_PRINCIPLED':
                        bsdf = node
                        break
                
                if bsdf:
                    # Check what is connected to Base Color
                    if bsdf.inputs['Base Color'].is_linked:
                        link = bsdf.inputs['Base Color'].links[0]
                        result["connections"].append({
                            "input": "Base Color",
                            "from_node": link.from_node.type,
                            "from_node_name": link.from_node.name
                        })
                        if link.from_node.type == 'TEX_IMAGE':
                            result["textures"]["diffuse"] = {
                                "node": link.from_node.name,
                                "image": link.from_node.image.name if link.from_node.image else None,
                                "colorspace": link.from_node.image.colorspace_settings.name if link.from_node.image else None
                            }

                    # Check what is connected to Roughness
                    if bsdf.inputs['Roughness'].is_linked:
                        link = bsdf.inputs['Roughness'].links[0]
                        result["connections"].append({
                            "input": "Roughness",
                            "from_node": link.from_node.type,
                            "from_node_name": link.from_node.name
                        })
                        if link.from_node.type == 'TEX_IMAGE':
                            result["textures"]["roughness"] = {
                                "node": link.from_node.name,
                                "image": link.from_node.image.name if link.from_node.image else None,
                                "colorspace": link.from_node.image.colorspace_settings.name if link.from_node.image else None
                            }

                    # Check what is connected to Normal
                    if bsdf.inputs['Normal'].is_linked:
                        link = bsdf.inputs['Normal'].links[0]
                        result["connections"].append({
                            "input": "Normal",
                            "from_node": link.from_node.type,
                            "from_node_name": link.from_node.name
                        })
                        
                        # If connected to Normal Map node, check what feeds into THAT
                        if link.from_node.type == 'NORMAL_MAP':
                            norm_map_node = link.from_node
                            if norm_map_node.inputs['Color'].is_linked:
                                sub_link = norm_map_node.inputs['Color'].links[0]
                                if sub_link.from_node.type == 'TEX_IMAGE':
                                    result["textures"]["normal"] = {
                                        "node": sub_link.from_node.name,
                                        "image": sub_link.from_node.image.name if sub_link.from_node.image else None,
                                        "colorspace": sub_link.from_node.image.colorspace_settings.name if sub_link.from_node.image else None,
                                        "via_normal_map_node": True
                                    }

except Exception as e:
    result["error"] = str(e)

print("JSON_START")
print(json.dumps(result))
print("JSON_END")
PYEOF

# Run analysis
ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
JSON_CONTENT=$(echo "$ANALYSIS_OUTPUT" | awk '/JSON_START/{flag=1; next} /JSON_END/{flag=0} flag')

# Construct final result
cat > /tmp/task_result.json << EOF
{
    "blend_exists": $BLEND_EXISTS,
    "render_exists": $RENDER_EXISTS,
    "render_size": $RENDER_SIZE,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "analysis": ${JSON_CONTENT:-null}
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="