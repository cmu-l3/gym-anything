#!/bin/bash
echo "=== Exporting freestyle_line_art_render result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
OUTPUT_BLEND="/home/ga/BlenderProjects/freestyle_setup.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/line_art_render.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ================================================================
# CHECK RENDER FILE
# ================================================================
RENDER_EXISTS="false"
RENDER_CREATED_DURING_TASK="false"
RENDER_SIZE="0"
RENDER_WIDTH="0"
RENDER_HEIGHT="0"

if [ -f "$OUTPUT_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$OUTPUT_RENDER" 2>/dev/null || echo "0")
    RENDER_MTIME=$(stat -c%Y "$OUTPUT_RENDER" 2>/dev/null || echo "0")
    
    if [ "$RENDER_MTIME" -gt "$TASK_START" ]; then
        RENDER_CREATED_DURING_TASK="true"
    fi

    # Get dimensions
    DIM_JSON=$(get_image_dimensions "$OUTPUT_RENDER")
    RENDER_WIDTH=$(echo "$DIM_JSON" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))")
    RENDER_HEIGHT=$(echo "$DIM_JSON" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))")
fi

# ================================================================
# CHECK BLEND FILE & ANALYZE SCENE
# ================================================================
BLEND_EXISTS="false"
BLEND_VALID="false"
SCENE_DATA="{}"

if [ -f "$OUTPUT_BLEND" ]; then
    BLEND_EXISTS="true"
    # Check magic bytes
    if [[ "$(head -c 7 "$OUTPUT_BLEND")" == "BLENDER" ]]; then
        BLEND_VALID="true"
        
        # Analyze scene with Blender Python
        ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_freestyle.XXXXXX.py)
        cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/freestyle_setup.blend")

scene = bpy.context.scene
vl = bpy.context.view_layer

# Check Freestyle
use_freestyle = scene.render.use_freestyle

# Check Line Sets
line_sets = []
if use_freestyle:
    for lineset in vl.freestyle_settings.linesets:
        ls_info = {
            "name": lineset.name,
            "enabled": lineset.show_line_set,
            "thickness": lineset.linestyle.thickness,
            "color": list(lineset.linestyle.color)
        }
        line_sets.append(ls_info)

# Check World Background
bg_color = [0.0, 0.0, 0.0]
if scene.world and scene.world.use_nodes:
    for node in scene.world.node_tree.nodes:
        if node.type == 'BACKGROUND':
            bg_color = list(node.inputs['Color'].default_value)[:3]
            break
elif scene.world:
    bg_color = list(scene.world.color)

result = {
    "use_freestyle": use_freestyle,
    "resolution_x": scene.render.resolution_x,
    "resolution_y": scene.render.resolution_y,
    "line_sets": line_sets,
    "world_color": bg_color
}
print("JSON_RESULT:" + json.dumps(result))
PYEOF

        # Run analysis
        ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
        SCENE_DATA=$(echo "$ANALYSIS_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
        rm -f "$ANALYSIS_SCRIPT"
    fi
fi

if [ -z "$SCENE_DATA" ]; then
    SCENE_DATA="{}"
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
cat > /tmp/task_result.json << EOF
{
    "render_exists": $RENDER_EXISTS,
    "render_created_during_task": $RENDER_CREATED_DURING_TASK,
    "render_size_bytes": $RENDER_SIZE,
    "render_width": $RENDER_WIDTH,
    "render_height": $RENDER_HEIGHT,
    "blend_exists": $BLEND_EXISTS,
    "blend_valid": $BLEND_VALID,
    "scene_data": $SCENE_DATA,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json