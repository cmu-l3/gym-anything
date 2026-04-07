#!/bin/bash
echo "=== Exporting compositing_product_pipeline result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_BLEND="/home/ga/BlenderProjects/composited_pipeline.blend"
EXPECTED_RENDER="/home/ga/BlenderProjects/bmw_composited.png"
RESULT_FILE="/tmp/task_result.json"

# ================================================================
# TAKE FINAL SCREENSHOT
# ================================================================
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ================================================================
# CHECK OUTPUT FILE EXISTENCE AND METADATA
# ================================================================
BLEND_EXISTS="false"
BLEND_SIZE=0
BLEND_MTIME=0

if [ -f "$EXPECTED_BLEND" ]; then
    BLEND_EXISTS="true"
    BLEND_SIZE=$(stat -c%s "$EXPECTED_BLEND" 2>/dev/null || echo "0")
    BLEND_MTIME=$(stat -c%Y "$EXPECTED_BLEND" 2>/dev/null || echo "0")
fi

RENDER_EXISTS="false"
RENDER_SIZE=0
RENDER_MTIME=0
IMAGE_WIDTH=0
IMAGE_HEIGHT=0
IMAGE_FORMAT="none"

if [ -f "$EXPECTED_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$EXPECTED_RENDER" 2>/dev/null || echo "0")
    RENDER_MTIME=$(stat -c%Y "$EXPECTED_RENDER" 2>/dev/null || echo "0")

    # Get image dimensions via PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/BlenderProjects/bmw_composited.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown"}))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error"}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))")
fi

# ================================================================
# ANALYZE BLEND FILE VIA HEADLESS BLENDER
# ================================================================
SCENE_ANALYSIS="{}"

# Try the expected output first, fall back to render_scene.blend
BLEND_TO_ANALYZE="$EXPECTED_BLEND"
if [ ! -f "$BLEND_TO_ANALYZE" ]; then
    BLEND_TO_ANALYZE="/home/ga/BlenderProjects/render_scene.blend"
fi

if [ -f "$BLEND_TO_ANALYZE" ]; then
    echo "Analyzing: $BLEND_TO_ANALYZE"

    ANALYZE_SCRIPT=$(mktemp /tmp/analyze_compositing.XXXXXX.py)
    cat > "$ANALYZE_SCRIPT" << PYEOF
import bpy
import json
import sys

try:
    bpy.ops.wm.open_mainfile(filepath="$BLEND_TO_ANALYZE")

    scene = bpy.context.scene
    vl = bpy.context.view_layer
    result = {"analysis_success": True}

    # --- Render Settings ---
    result["render_engine"] = scene.render.engine
    result["cycles_samples"] = scene.cycles.samples if scene.render.engine == 'CYCLES' else -1
    result["resolution_x"] = scene.render.resolution_x
    result["resolution_y"] = scene.render.resolution_y
    result["resolution_percentage"] = scene.render.resolution_percentage

    # --- Render Passes ---
    result["pass_ao"] = vl.use_pass_ambient_occlusion
    result["pass_mist"] = vl.use_pass_mist
    result["pass_z"] = vl.use_pass_z

    # --- Mist Settings ---
    if scene.world:
        result["mist_start"] = round(scene.world.mist_settings.start, 2)
        result["mist_depth"] = round(scene.world.mist_settings.depth, 2)
    else:
        result["mist_start"] = -1
        result["mist_depth"] = -1

    # --- Compositor Analysis ---
    result["use_nodes"] = scene.use_nodes
    result["compositor_nodes"] = []
    result["compositor_links"] = []

    if scene.use_nodes and scene.node_tree:
        tree = scene.node_tree

        # Collect all nodes with type-specific parameters
        for node in tree.nodes:
            node_info = {
                "name": node.name,
                "type": node.type,
                "bl_idname": node.bl_idname
            }

            if node.type == 'GLARE':
                node_info["glare_type"] = node.glare_type
                node_info["quality"] = node.quality
                node_info["threshold"] = round(node.threshold, 3)
                node_info["size"] = node.size
                node_info["mix"] = round(node.mix, 3)

            elif node.type == 'COLORBALANCE':
                node_info["correction_method"] = node.correction_method
                node_info["gain"] = [round(v, 4) for v in node.gain[:3]]
                node_info["lift"] = [round(v, 4) for v in node.lift[:3]]
                node_info["gamma"] = [round(v, 4) for v in node.gamma[:3]]

            elif node.type == 'MAP_VALUE':
                node_info["offset"] = [round(node.offset[0], 4)]
                node_info["size_val"] = [round(node.size[0], 4)]
                node_info["use_min"] = node.use_min
                node_info["use_max"] = node.use_max
                node_info["min_val"] = [round(node.min[0], 4)]
                node_info["max_val"] = [round(node.max[0], 4)]

            elif node.type == 'MIX_RGB':
                node_info["blend_type"] = node.blend_type
                # MixRGB inputs by index: 0=Fac, 1=Image(top/A), 2=Image(bottom/B)
                if len(node.inputs) >= 1:
                    node_info["fac_default"] = round(node.inputs[0].default_value, 4)
                if len(node.inputs) >= 3:
                    # Second image input (bottom / Color2 / B) - the fog color
                    inp2 = node.inputs[2]
                    if hasattr(inp2, 'default_value') and hasattr(inp2.default_value, '__len__'):
                        node_info["color2_default"] = [round(v, 4) for v in inp2.default_value[:3]]

            elif node.type == 'OUTPUT_FILE':
                node_info["base_path"] = node.base_path
                node_info["file_slots"] = []
                if node.file_slots:
                    for slot in node.file_slots:
                        node_info["file_slots"].append({"path": slot.path})

            elif node.type == 'R_LAYERS':
                node_info["layer"] = node.layer if hasattr(node, 'layer') else ""

            elif node.type == 'COMPOSITE':
                pass  # No extra params needed

            result["compositor_nodes"].append(node_info)

        # Collect all links
        for link in tree.links:
            result["compositor_links"].append({
                "from_node": link.from_node.name,
                "from_socket": link.from_socket.name,
                "to_node": link.to_node.name,
                "to_socket": link.to_socket.name
            })

    print("ANALYSIS_JSON:" + json.dumps(result))

except Exception as e:
    print("ANALYSIS_JSON:" + json.dumps({"analysis_success": False, "error": str(e)}))
PYEOF

    ANALYZE_OUTPUT=$(/opt/blender/blender --background --python "$ANALYZE_SCRIPT" 2>/dev/null)
    ANALYSIS_LINE=$(echo "$ANALYZE_OUTPUT" | grep "^ANALYSIS_JSON:" | head -1)

    if [ -n "$ANALYSIS_LINE" ]; then
        SCENE_ANALYSIS="${ANALYSIS_LINE#ANALYSIS_JSON:}"
    else
        echo "WARNING: Could not extract analysis from Blender output"
        SCENE_ANALYSIS='{"analysis_success": false, "error": "Failed to extract JSON"}'
    fi

    rm -f "$ANALYZE_SCRIPT"
fi

# ================================================================
# CREATE FINAL RESULT JSON
# ================================================================
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "blend_exists": $BLEND_EXISTS,
    "blend_size_bytes": $BLEND_SIZE,
    "blend_mtime": $BLEND_MTIME,
    "blend_path": "$EXPECTED_BLEND",
    "render_exists": $RENDER_EXISTS,
    "render_size_bytes": $RENDER_SIZE,
    "render_mtime": $RENDER_MTIME,
    "render_path": "$EXPECTED_RENDER",
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "scene_analysis": $SCENE_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result:"
cat "$RESULT_FILE"
echo "=== Export complete ==="
