#!/bin/bash
echo "=== Exporting texture_paint_wear_mask result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Directories
PROJECT_DIR="/home/ga/BlenderProjects"
IMAGE_PATH="$PROJECT_DIR/wear_mask.png"
BLEND_PATH="$PROJECT_DIR/distressed_crate.blend"

# Take final screenshot
take_screenshot /tmp/task_end.png

# ================================================================
# ANALYZE SAVED IMAGE (Programmatic Content Check)
# ================================================================
# We check if the image is just solid black or solid white
IMAGE_ANALYSIS="{}"
if [ -f "$IMAGE_PATH" ]; then
    IMAGE_ANALYSIS=$(python3 << PYEOF
import json
import numpy as np
try:
    from PIL import Image
    img = Image.open("$IMAGE_PATH").convert('L') # Convert to grayscale
    arr = np.array(img)
    
    # Calculate stats
    mean_val = float(np.mean(arr))
    max_val = float(np.max(arr))
    min_val = float(np.min(arr))
    variance = float(np.var(arr))
    
    # Check if painting occurred
    # Assuming black background (0), white paint (255)
    # If mean is > 0 and < 255, and variance > 0, it has content
    has_content = variance > 0 and mean_val > 0
    
    # Check if it's just a solid bucket fill (variance 0 but mean > 0)
    is_solid_fill = variance == 0 and mean_val > 0
    
    print(json.dumps({
        "exists": True,
        "width": img.width,
        "height": img.height,
        "mean_intensity": mean_val,
        "variance": variance,
        "has_content": has_content,
        "is_solid_fill": is_solid_fill
    }))
except Exception as e:
    print(json.dumps({"exists": False, "error": str(e)}))
PYEOF
)
else
    IMAGE_ANALYSIS='{"exists": false}'
fi

# ================================================================
# ANALYZE BLEND FILE (Node Graph & UV Check)
# ================================================================
SCENE_ANALYSIS="{}"
if [ -f "$BLEND_PATH" ]; then
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_nodes.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/distressed_crate.blend")

result = {
    "uvs_exist": False,
    "image_node_found": False,
    "image_assigned": False,
    "mix_node_found": False,
    "links_correct": False,
    "material_name": None
}

obj = bpy.data.objects.get("SciFiCrate")
if obj and obj.type == 'MESH':
    # Check UVs
    if obj.data.uv_layers:
        result["uvs_exist"] = True
        
    # Check Material
    if obj.data.materials:
        mat = obj.data.materials[0]
        result["material_name"] = mat.name
        
        if mat.use_nodes and mat.node_tree:
            nodes = mat.node_tree.nodes
            links = mat.node_tree.links
            
            # Find Image Texture Node
            img_node = None
            for n in nodes:
                if n.type == 'TEX_IMAGE':
                    # Check if it references 'wear_mask'
                    if n.image and "wear_mask" in n.image.name.lower():
                        result["image_node_found"] = True
                        result["image_assigned"] = True
                        img_node = n
                        break
                    # Or just any image node if they named it differently but linked it
                    elif n.image:
                        # Fallback check
                        pass

            # Find Mix Node (Mix Shader or Mix RGB)
            mix_node = None
            for n in nodes:
                if n.type in ['MIX_SHADER', 'MIX_RGB', 'MIX']:
                    # Simple heuristic: Does it have inputs connected?
                    mix_node = n
                    result["mix_node_found"] = True
                    # If we found an image node, check if it links to this mix node
                    if img_node:
                        # Check links
                        for link in links:
                            if link.from_node == img_node and link.to_node == mix_node:
                                # Check if connected to Factor (usually input 0)
                                if "Fac" in link.to_socket.name:
                                    result["links_correct"] = True
                                    break
                    if result["links_correct"]:
                        break

print("JSON:" + json.dumps(result))
PYEOF

    CMD_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    SCENE_ANALYSIS=$(echo "$CMD_OUTPUT" | grep '^JSON:' | sed 's/^JSON://')
    rm -f "$ANALYSIS_SCRIPT"
fi

# Use default JSON if extraction failed
if [ -z "$SCENE_ANALYSIS" ]; then SCENE_ANALYSIS='{"error": "Failed to analyze blend file"}'; fi

# Combine Results
cat > /tmp/task_result.json << EOF
{
    "image_analysis": $IMAGE_ANALYSIS,
    "scene_analysis": $SCENE_ANALYSIS,
    "image_path_exists": $([ -f "$IMAGE_PATH" ] && echo "true" || echo "false"),
    "blend_path_exists": $([ -f "$BLEND_PATH" ] && echo "true" || echo "false"),
    "task_end_time": $(date +%s)
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json