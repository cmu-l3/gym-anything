#!/bin/bash
echo "=== Exporting chroma_key_compositing result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BLEND_FILE="/home/ga/BlenderProjects/chroma_key.blend"
RENDER_FILE="/home/ga/BlenderProjects/keyed_subject.png"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence
BLEND_EXISTS="false"
[ -f "$BLEND_FILE" ] && BLEND_EXISTS="true"

RENDER_EXISTS="false"
RENDER_SIZE="0"
if [ -f "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$RENDER_FILE")
fi

# Analyze Blender File (Headless)
# We check:
# 1. Compositor Use Nodes is True
# 2. Render settings (PNG, RGBA)
# 3. Node Graph contains Keying node
# 4. Input image is loaded

ANALYSIS_JSON="{}"
if [ "$BLEND_EXISTS" = "true" ]; then
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_compositor.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import os

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/chroma_key.blend")
    
    scene = bpy.context.scene
    
    # Check Render Settings
    render_settings = {
        "file_format": scene.render.image_settings.file_format,
        "color_mode": scene.render.image_settings.color_mode,
        "resolution_x": scene.render.resolution_x,
        "resolution_y": scene.render.resolution_y
    }
    
    # Check Compositor Nodes
    compositor_data = {
        "use_nodes": scene.use_nodes,
        "nodes": [],
        "has_keying_node": False,
        "has_image_input": False,
        "has_composite_output": False,
        "links_valid": False
    }
    
    if scene.use_nodes and scene.node_tree:
        tree = scene.node_tree
        
        # List nodes
        for node in tree.nodes:
            compositor_data["nodes"].append(node.type)
            
            # Check for Keying nodes (Keying, Chroma Matte, Color Spill, or manual math nodes)
            if node.type in ['KEYING', 'CHROMA_MATTE', 'COLOR_SPILL', 'DIFFERENCE_MATTE', 'CHANNEL_MATTE', 'LUMA_MATTE']:
                compositor_data["has_keying_node"] = True
            
            # Check input
            if node.type == 'IMAGE':
                if node.image:
                    compositor_data["has_image_input"] = True
            
            # Check output
            if node.type == 'COMPOSITE':
                compositor_data["has_composite_output"] = True
                
        # Check connectivity (Simple check: is there a path from Image to Composite?)
        # This is complex to walk, but we can just check if both exist and links > 0
        if len(tree.links) > 0 and compositor_data["has_image_input"] and compositor_data["has_composite_output"]:
            compositor_data["links_valid"] = True

    result = {
        "render": render_settings,
        "compositor": compositor_data,
        "success": True
    }
    
except Exception as e:
    result = {
        "success": False,
        "error": str(e)
    }

print("JSON_START" + json.dumps(result) + "JSON_END")
PYEOF

    # Run Blender Python
    RAW_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    # Extract JSON
    ANALYSIS_JSON=$(echo "$RAW_OUTPUT" | grep -o "JSON_START.*JSON_END" | sed 's/JSON_START//;s/JSON_END//')
    rm -f "$ANALYSIS_SCRIPT"
fi

# Prepare final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "blend_exists": $BLEND_EXISTS,
    "render_exists": $RENDER_EXISTS,
    "render_size": $RENDER_SIZE,
    "scene_analysis": ${ANALYSIS_JSON:-{}},
    "screenshot_path": "/tmp/task_final.png",
    "render_path": "/home/ga/BlenderProjects/keyed_subject.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json