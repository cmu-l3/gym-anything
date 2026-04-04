#!/bin/bash
echo "=== Exporting HDRI Studio Noir results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_BLEND="/home/ga/BlenderProjects/noir_setup.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/noir_render.png"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ================================================================
# 1. CHECK FILE EXISTENCE
# ================================================================
BLEND_EXISTS="false"
RENDER_EXISTS="false"
RENDER_SIZE="0"

if [ -f "$OUTPUT_BLEND" ]; then BLEND_EXISTS="true"; fi
if [ -f "$OUTPUT_RENDER" ]; then 
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$OUTPUT_RENDER" 2>/dev/null || echo "0")
fi

# ================================================================
# 2. ANALYZE BLEND FILE WITH PYTHON
# ================================================================
# We inspect the World Node Tree to verify the configuration
cat > /tmp/analyze_noir.py << 'PYEOF'
import bpy
import json
import math
import os

result = {
    "world_use_nodes": False,
    "nodes_found": [],
    "hdri_image": None,
    "mapping_rotation_z": None,
    "saturation": None,
    "is_connected": False
}

try:
    # Open the file
    filepath = "/home/ga/BlenderProjects/noir_setup.blend"
    if os.path.exists(filepath):
        bpy.ops.wm.open_mainfile(filepath=filepath)
        
        world = bpy.context.scene.world
        if world and world.use_nodes and world.node_tree:
            result["world_use_nodes"] = True
            tree = world.node_tree
            nodes = tree.nodes
            
            # Find specific nodes by type
            env_node = None
            mapping_node = None
            hsv_node = None
            bg_node = None
            
            for node in nodes:
                result["nodes_found"].append(node.type)
                
                if node.type == 'TEX_ENVIRONMENT':
                    env_node = node
                    if node.image:
                        result["hdri_image"] = node.image.name
                        
                elif node.type == 'MAPPING':
                    mapping_node = node
                    # Blender 2.8+ uses .rotation[2] for Z
                    result["mapping_rotation_z"] = node.inputs['Rotation'].default_value[2]
                    
                elif node.type == 'HUE_SATURATION':
                    hsv_node = node
                    result["saturation"] = node.inputs['Saturation'].default_value
                    
                elif node.type == 'BACKGROUND':
                    bg_node = node

            # Check connectivity (simplified chain check)
            # We want: ... -> HSV -> Background
            if hsv_node and bg_node:
                # Check if HSV connects to Background
                # Iterate links
                for link in tree.links:
                    if link.from_node == hsv_node and link.to_node == bg_node:
                        result["is_connected"] = True
                        break
            
except Exception as e:
    result["error"] = str(e)

print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run analysis
ANALYSIS_JSON="{}"
if [ "$BLEND_EXISTS" = "true" ]; then
    RAW_OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_noir.py 2>/dev/null)
    ANALYSIS_JSON=$(echo "$RAW_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
fi

# ================================================================
# 3. COMPILE FINAL JSON
# ================================================================
# Use python to merge simple shell vars with complex analysis json
cat > /tmp/merge_results.py << PYEOF
import json
import sys

try:
    analysis = json.loads('''$ANALYSIS_JSON''' or '{}')
    
    final_result = {
        "task_start": $TASK_START,
        "task_end": $TASK_END,
        "blend_exists": "$BLEND_EXISTS" == "true",
        "render_exists": "$RENDER_EXISTS" == "true",
        "render_size_bytes": int("$RENDER_SIZE"),
        "analysis": analysis,
        "screenshot_path": "/tmp/task_final.png"
    }
    
    with open("/tmp/task_result.json", "w") as f:
        json.dump(final_result, f, indent=2)
        
except Exception as e:
    print(f"Error merging JSON: {e}")
PYEOF

python3 /tmp/merge_results.py
rm -f /tmp/analyze_noir.py /tmp/merge_results.py

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json