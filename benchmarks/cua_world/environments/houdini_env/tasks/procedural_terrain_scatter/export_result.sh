#!/bin/bash
echo "=== Exporting procedural_terrain_scatter result ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_SCENE="/home/ga/HoudiniProjects/terrain_environment.hipnc"
RENDER_PATH="/home/ga/HoudiniProjects/renders/terrain_render.png"
HFS_DIR=$(get_hfs_dir)

# ================================================================
# CHECK OUTPUT SCENE
# ================================================================
SCENE_EXISTS="false"
SCENE_SIZE="0"

if [ -f "$OUTPUT_SCENE" ]; then
    SCENE_EXISTS="true"
    SCENE_SIZE=$(stat -c%s "$OUTPUT_SCENE" 2>/dev/null || echo "0")
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

# Also check common alternative render output locations
for alt_path in \
    "/home/ga/HoudiniProjects/renders/terrain_render.exr" \
    "/home/ga/HoudiniProjects/renders/terrain_render.jpg" \
    "/tmp/terrain_render.png" \
    "/home/ga/HoudiniProjects/renders/"*; do
    if [ -f "$alt_path" ] && [ "$RENDER_EXISTS" = "false" ]; then
        RENDER_EXISTS="true"
        RENDER_PATH="$alt_path"
        RENDER_SIZE=$(stat -c%s "$alt_path" 2>/dev/null || echo "0")
        RENDER_MIME=$(file -b --mime-type "$alt_path" 2>/dev/null || echo "unknown")
    fi
done

# ================================================================
# ANALYZE SCENE WITH HYTHON (comprehensive checks)
# ================================================================
SCENE_ANALYSIS='{"error": "scene not found"}'

if [ "$SCENE_EXISTS" = "true" ]; then
    SCENE_ANALYSIS=$("$HFS_DIR/bin/hython" -c "
import hou
import json

hou.hipFile.load('$OUTPUT_SCENE')

result = {
    'has_heightfield': False,
    'heightfield_node_types': [],
    'has_erosion': False,
    'erosion_node_types': [],
    'has_scatter_or_copy': False,
    'scatter_copy_node_types': [],
    'scatter_point_count': 0,
    'has_material': False,
    'material_names': [],
    'has_env_light': False,
    'env_light_hdri_path': '',
    'has_camera': False,
    'camera_names': [],
    'has_render_node': False,
    'render_node_types': [],
    'obj_node_count': 0,
    'total_geo_nodes': 0,
}

# ============================================================
# Check all nodes under /obj recursively
# ============================================================
obj_node = hou.node('/obj')
if obj_node:
    obj_children = obj_node.children()
    result['obj_node_count'] = len(obj_children)

    for child in obj_children:
        type_name = child.type().name().lower()

        # --- HeightField terrain check ---
        if 'heightfield' in type_name or type_name in ('terrain', 'heightfield'):
            result['has_heightfield'] = True
            result['heightfield_node_types'].append(child.type().name())

        # --- Environment light check ---
        if type_name in ('envlight', 'environment_light', 'env_light'):
            result['has_env_light'] = True
            # Check for HDRI map path
            for parm_name in ('env_map', 'ar_light_color_texture', 'light_color_texture', 'env_mappath'):
                p = child.parm(parm_name)
                if p:
                    val = p.eval()
                    if val and isinstance(val, str) and len(val) > 0:
                        result['env_light_hdri_path'] = val
                        break

        # --- Camera check ---
        if type_name in ('cam', 'camera', 'stereocam'):
            result['has_camera'] = True
            result['camera_names'].append(child.name())

        # --- GEO nodes: check SOPs inside ---
        if type_name == 'geo':
            result['total_geo_nodes'] += 1
            try:
                for sop in child.allSubChildren():
                    sop_type = sop.type().name().lower()

                    # HeightField SOP checks
                    if 'heightfield' in sop_type:
                        result['has_heightfield'] = True
                        if sop.type().name() not in result['heightfield_node_types']:
                            result['heightfield_node_types'].append(sop.type().name())

                    # Erosion checks
                    if any(kw in sop_type for kw in ('erode', 'erosion', 'heightfield_erode')):
                        result['has_erosion'] = True
                        if sop.type().name() not in result['erosion_node_types']:
                            result['erosion_node_types'].append(sop.type().name())

                    # Scatter / Copy-to-Points checks
                    if any(kw in sop_type for kw in ('copytopoints', 'copy', 'scatter', 'instance', 'copyxform')):
                        result['has_scatter_or_copy'] = True
                        if sop.type().name() not in result['scatter_copy_node_types']:
                            result['scatter_copy_node_types'].append(sop.type().name())

                        # Try to count output points on copy/scatter nodes
                        try:
                            geo_out = sop.geometry()
                            if geo_out:
                                pt_count = len(geo_out.points())
                                if pt_count > result['scatter_point_count']:
                                    result['scatter_point_count'] = pt_count
                        except:
                            pass
            except:
                pass

# ============================================================
# Check /mat for materials
# ============================================================
mat_node = hou.node('/mat')
if mat_node:
    mat_children = mat_node.children()
    if len(mat_children) > 0:
        result['has_material'] = True
        result['material_names'] = [m.name() for m in mat_children]

# ============================================================
# Check /out for render nodes
# ============================================================
out_node = hou.node('/out')
if out_node:
    for child in out_node.children():
        type_name = child.type().name().lower()
        if any(kw in type_name for kw in ('mantra', 'ifd', 'karma', 'opengl', 'ris')):
            result['has_render_node'] = True
            if child.type().name() not in result['render_node_types']:
                result['render_node_types'].append(child.type().name())

print(json.dumps(result))
" 2>/dev/null || echo '{"error": "hython analysis failed"}')
fi

echo "Scene analysis: $SCENE_ANALYSIS"

# ================================================================
# PARSE ANALYSIS RESULTS
# ================================================================
HAS_HEIGHTFIELD=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_heightfield') else 'false')" 2>/dev/null || echo "false")
HAS_EROSION=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_erosion') else 'false')" 2>/dev/null || echo "false")
HAS_SCATTER=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_scatter_or_copy') else 'false')" 2>/dev/null || echo "false")
SCATTER_COUNT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('scatter_point_count', 0))" 2>/dev/null || echo "0")
HAS_MATERIAL=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_material') else 'false')" 2>/dev/null || echo "false")
HAS_ENV_LIGHT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_env_light') else 'false')" 2>/dev/null || echo "false")
ENV_LIGHT_HDRI=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('env_light_hdri_path', ''))" 2>/dev/null || echo "")
HAS_CAMERA=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_camera') else 'false')" 2>/dev/null || echo "false")
HAS_RENDER_NODE=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_render_node') else 'false')" 2>/dev/null || echo "false")
HEIGHTFIELD_TYPES=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('heightfield_node_types', [])))" 2>/dev/null || echo "[]")
EROSION_TYPES=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('erosion_node_types', [])))" 2>/dev/null || echo "[]")
SCATTER_TYPES=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('scatter_copy_node_types', [])))" 2>/dev/null || echo "[]")
MATERIAL_NAMES=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('material_names', [])))" 2>/dev/null || echo "[]")
RENDER_NODE_TYPES=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('render_node_types', [])))" 2>/dev/null || echo "[]")

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
    "render_exists": $RENDER_EXISTS,
    "render_size_bytes": $RENDER_SIZE,
    "render_mime_type": "$RENDER_MIME",
    "render_path": "$RENDER_PATH",
    "has_heightfield": $HAS_HEIGHTFIELD,
    "heightfield_node_types": $HEIGHTFIELD_TYPES,
    "has_erosion": $HAS_EROSION,
    "erosion_node_types": $EROSION_TYPES,
    "has_scatter_or_copy": $HAS_SCATTER,
    "scatter_copy_node_types": $SCATTER_TYPES,
    "scatter_point_count": $SCATTER_COUNT,
    "has_material": $HAS_MATERIAL,
    "material_names": $MATERIAL_NAMES,
    "has_env_light": $HAS_ENV_LIGHT,
    "env_light_hdri_path": "$ENV_LIGHT_HDRI",
    "has_camera": $HAS_CAMERA,
    "has_render_node": $HAS_RENDER_NODE,
    "render_node_types": $RENDER_NODE_TYPES,
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
