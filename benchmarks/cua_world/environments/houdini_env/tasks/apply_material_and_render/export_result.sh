#!/bin/bash
echo "=== Exporting apply_material_and_render result ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_SCENE="/home/ga/HoudiniProjects/bunny_material.hipnc"
RENDER_PATH="/home/ga/HoudiniProjects/renders/bunny_render.png"
HFS_DIR=$(get_hfs_dir)

# ================================================================
# CHECK OUTPUT SCENE
# ================================================================
SCENE_EXISTS="false"
SCENE_SIZE="0"
SCENE_CREATED="false"

if [ -f "$OUTPUT_SCENE" ]; then
    SCENE_EXISTS="true"
    SCENE_SIZE=$(stat -c%s "$OUTPUT_SCENE" 2>/dev/null || echo "0")
    SCENE_CREATED="true"
fi

# ================================================================
# CHECK RENDER OUTPUT
# ================================================================
RENDER_EXISTS="false"
RENDER_SIZE="0"
RENDER_MIME=""

if [ -f "$RENDER_PATH" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$RENDER_PATH" 2>/dev/null || echo "0")
    RENDER_MIME=$(file -b --mime-type "$RENDER_PATH" 2>/dev/null || echo "unknown")
fi

# Also check common render output locations
for alt_path in \
    "/home/ga/HoudiniProjects/renders/bunny_render.exr" \
    "/home/ga/HoudiniProjects/renders/bunny_render.jpg" \
    "/tmp/bunny_render.png" \
    "/home/ga/HoudiniProjects/renders/"*; do
    if [ -f "$alt_path" ] && [ "$RENDER_EXISTS" = "false" ]; then
        RENDER_EXISTS="true"
        RENDER_PATH="$alt_path"
        RENDER_SIZE=$(stat -c%s "$alt_path" 2>/dev/null || echo "0")
        RENDER_MIME=$(file -b --mime-type "$alt_path" 2>/dev/null || echo "unknown")
    fi
done

# ================================================================
# ANALYZE SCENE WITH HYTHON
# ================================================================
HAS_MATERIAL="false"
MATERIAL_TYPE=""
MATERIAL_NAME=""
BASE_COLOR_R="0"
BASE_COLOR_G="0"
BASE_COLOR_B="0"
METALLIC="0"
ROUGHNESS="0"
MATERIAL_ASSIGNED="false"
HAS_RENDER_NODE="false"
RENDER_NODE_TYPE=""

if [ "$SCENE_EXISTS" = "true" ]; then
    SCENE_ANALYSIS=$("$HFS_DIR/bin/hython" -c "
import hou
import json

hou.hipFile.load('$OUTPUT_SCENE')

result = {
    'has_material': False,
    'material_type': '',
    'material_name': '',
    'base_color': [0, 0, 0],
    'metallic': 0,
    'roughness': 0,
    'material_assigned': False,
    'assigned_to': '',
    'has_render_node': False,
    'render_node_type': '',
    'render_output': '',
}

# Check /mat context for materials
mat_node = hou.node('/mat')
if mat_node:
    for child in mat_node.children():
        type_name = child.type().name()
        if 'principled' in type_name.lower() or 'shader' in type_name.lower():
            result['has_material'] = True
            result['material_type'] = type_name
            result['material_name'] = child.name()

            # Try to read parameters
            try:
                result['base_color'] = [
                    child.parm('basecolorr').eval() if child.parm('basecolorr') else 0,
                    child.parm('basecolorg').eval() if child.parm('basecolorg') else 0,
                    child.parm('basecolorb').eval() if child.parm('basecolorb') else 0,
                ]
            except:
                try:
                    result['base_color'] = [
                        child.parm('basecolor_r').eval() if child.parm('basecolor_r') else 0,
                        child.parm('basecolor_g').eval() if child.parm('basecolor_g') else 0,
                        child.parm('basecolor_b').eval() if child.parm('basecolor_b') else 0,
                    ]
                except:
                    pass

            try:
                result['metallic'] = child.parm('metallic').eval() if child.parm('metallic') else 0
            except:
                pass

            try:
                result['roughness'] = child.parm('rough').eval() if child.parm('rough') else \
                    (child.parm('roughness').eval() if child.parm('roughness') else 0)
            except:
                pass
            break

# Check if material is assigned to bunny
for obj_node in hou.node('/obj').children():
    if obj_node.type().name() == 'geo':
        shop_path = obj_node.parm('shop_materialpath')
        if shop_path and shop_path.eval():
            mat_path = shop_path.eval()
            if mat_path:
                result['material_assigned'] = True
                result['assigned_to'] = obj_node.name()
                break
        # Also check via material SOP inside the geo
        for child in obj_node.children():
            if child.type().name() == 'material':
                result['material_assigned'] = True
                result['assigned_to'] = obj_node.name()
                break

# Check /out for render nodes
out_node = hou.node('/out')
if out_node:
    for child in out_node.children():
        type_name = child.type().name()
        if 'mantra' in type_name.lower() or 'ifd' in type_name.lower() or 'karma' in type_name.lower():
            result['has_render_node'] = True
            result['render_node_type'] = type_name
            try:
                vm_picture = child.parm('vm_picture')
                if vm_picture:
                    result['render_output'] = vm_picture.eval()
            except:
                pass
            break

print(json.dumps(result))
" 2>/dev/null || echo '{"error": "hython failed"}')

    if [ -n "$SCENE_ANALYSIS" ]; then
        HAS_MATERIAL=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_material') else 'false')" 2>/dev/null || echo "false")
        MATERIAL_TYPE=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('material_type', ''))" 2>/dev/null || echo "")
        MATERIAL_NAME=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('material_name', ''))" 2>/dev/null || echo "")
        BASE_COLOR_R=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('base_color', [0,0,0])[0])" 2>/dev/null || echo "0")
        BASE_COLOR_G=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('base_color', [0,0,0])[1])" 2>/dev/null || echo "0")
        BASE_COLOR_B=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('base_color', [0,0,0])[2])" 2>/dev/null || echo "0")
        METALLIC=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('metallic', 0))" 2>/dev/null || echo "0")
        ROUGHNESS=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('roughness', 0))" 2>/dev/null || echo "0")
        MATERIAL_ASSIGNED=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('material_assigned') else 'false')" 2>/dev/null || echo "false")
        HAS_RENDER_NODE=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_render_node') else 'false')" 2>/dev/null || echo "false")
        RENDER_NODE_TYPE=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('render_node_type', ''))" 2>/dev/null || echo "")
    fi
fi

# ================================================================
# CHECK HOUDINI STATE
# ================================================================
HOUDINI_RUNNING="false"
if is_houdini_running | grep -q "true"; then
    HOUDINI_RUNNING="true"
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "scene_exists": $SCENE_EXISTS,
    "scene_size_bytes": $SCENE_SIZE,
    "scene_created": $SCENE_CREATED,
    "render_exists": $RENDER_EXISTS,
    "render_size_bytes": $RENDER_SIZE,
    "render_mime_type": "$RENDER_MIME",
    "render_path": "$RENDER_PATH",
    "has_material": $HAS_MATERIAL,
    "material_type": "$MATERIAL_TYPE",
    "material_name": "$MATERIAL_NAME",
    "base_color": [$BASE_COLOR_R, $BASE_COLOR_G, $BASE_COLOR_B],
    "metallic": $METALLIC,
    "roughness": $ROUGHNESS,
    "material_assigned": $MATERIAL_ASSIGNED,
    "has_render_node": $HAS_RENDER_NODE,
    "render_node_type": "$RENDER_NODE_TYPE",
    "houdini_was_running": $HOUDINI_RUNNING,
    "screenshot_path": "/tmp/task_end.png",
    "initial_screenshot_path": "/tmp/task_start.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
