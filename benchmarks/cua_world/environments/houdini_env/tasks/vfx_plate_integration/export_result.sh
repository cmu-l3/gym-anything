#!/bin/bash
echo "=== Exporting vfx_plate_integration result ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_SCENE="/home/ga/HoudiniProjects/vfx_integration.hipnc"
RENDER_DIR="/home/ga/HoudiniProjects/renders/integration"
COMPOSITE_PATH="$RENDER_DIR/final_comp.exr"
BG_PLATE="/home/ga/HoudiniProjects/data/bg_plate.jpg"
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
# CHECK RENDERED FILES IN integration/ DIRECTORY
# ================================================================
RENDER_FILE_COUNT="0"
RENDER_FILES="[]"
COMPOSITE_EXISTS="false"
COMPOSITE_SIZE="0"

if [ -d "$RENDER_DIR" ]; then
    RENDER_FILE_COUNT=$(find "$RENDER_DIR" -type f \( -name "*.exr" -o -name "*.png" -o -name "*.jpg" -o -name "*.tif" -o -name "*.tiff" \) 2>/dev/null | wc -l)
    RENDER_FILES=$(find "$RENDER_DIR" -type f \( -name "*.exr" -o -name "*.png" -o -name "*.jpg" -o -name "*.tif" -o -name "*.tiff" \) 2>/dev/null | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin]))" 2>/dev/null || echo "[]")
fi

if [ -f "$COMPOSITE_PATH" ]; then
    COMPOSITE_EXISTS="true"
    COMPOSITE_SIZE=$(stat -c%s "$COMPOSITE_PATH" 2>/dev/null || echo "0")
fi

# ================================================================
# ANALYZE SCENE WITH HYTHON
# ================================================================
SCENE_ANALYSIS='{"error": "scene not found"}'

if [ "$SCENE_EXISTS" = "true" ]; then
    SCENE_ANALYSIS=$("$HFS_DIR/bin/hython" -c "
import hou
import json

hou.hipFile.load('$OUTPUT_SCENE')

result = {
    # Materials
    'has_shadow_catcher_material': False,
    'shadow_catcher_material_name': '',
    'has_chrome_material': False,
    'chrome_material_name': '',
    'chrome_metallic': 0.0,
    'chrome_roughness': 1.0,
    'material_names': [],
    'material_types': [],

    # Ground plane
    'has_ground_plane': False,
    'ground_plane_name': '',
    'ground_plane_has_material': False,
    'ground_plane_material_path': '',

    # Bunny material assignment
    'bunny_has_material': False,
    'bunny_material_path': '',

    # Mantra / render setup
    'has_mantra_node': False,
    'mantra_output_path': '',
    'has_separate_passes': False,
    'pass_count': 0,
    'pass_paths': [],
    'extra_image_planes': [],

    # COP2 network
    'has_cop_network': False,
    'cop_node_count': 0,
    'cop_node_names': [],
    'cop_node_types': [],
    'cop_references_bg_plate': False,
    'cop_has_composite_op': False,
    'cop_has_output_rop': False,
}

# ============================================================
# CHECK /mat FOR MATERIALS
# ============================================================
mat_node = hou.node('/mat')
if mat_node:
    for child in mat_node.children():
        type_name = child.type().name().lower()
        child_name = child.name().lower()
        result['material_names'].append(child.name())
        result['material_types'].append(child.type().name())

        # ----- Shadow catcher / matte material -----
        is_matte = False
        # Check name for matte/shadow_catcher keywords
        if any(kw in child_name for kw in ('matte', 'shadow_catcher', 'shadowcatcher', 'shadow', 'catcher', 'holdout')):
            is_matte = True
        # Check type
        if any(kw in type_name for kw in ('matte', 'shadowmatte')):
            is_matte = True
        # Check for matte parameter inside principled or VOP networks
        if 'principled' in type_name or 'shader' in type_name:
            # Check for matte_shading or opacity being set for matte behavior
            for pname in ('matte_shading', 'enable_matte', 'Categories'):
                p = child.parm(pname)
                if p:
                    try:
                        val = p.eval()
                        if val:
                            is_matte = True
                    except:
                        pass
        # If it is a VOP network, scan children for matte-related nodes
        if type_name in ('materialbuilder', 'vopmaterial', 'subnet', 'matnet'):
            try:
                for sub in child.allSubChildren():
                    sub_type = sub.type().name().lower()
                    if any(kw in sub_type for kw in ('matte', 'shadowmatte', 'holdout', 'phantom')):
                        is_matte = True
                        break
            except:
                pass

        if is_matte:
            result['has_shadow_catcher_material'] = True
            result['shadow_catcher_material_name'] = child.name()

        # ----- Chrome / reflective material -----
        is_chrome = False
        if any(kw in child_name for kw in ('chrome', 'metal', 'reflective', 'mirror', 'steel', 'silver')):
            is_chrome = True
        if 'principled' in type_name or 'shader' in type_name:
            metallic_val = 0.0
            roughness_val = 1.0
            try:
                mp = child.parm('metallic')
                if mp:
                    metallic_val = mp.eval()
            except:
                pass
            try:
                rp = child.parm('rough')
                if not rp:
                    rp = child.parm('roughness')
                if rp:
                    roughness_val = rp.eval()
            except:
                pass
            result['chrome_metallic'] = metallic_val
            result['chrome_roughness'] = roughness_val
            if metallic_val > 0.5:
                is_chrome = True
        if is_chrome:
            result['has_chrome_material'] = True
            result['chrome_material_name'] = child.name()

# ============================================================
# CHECK /obj FOR GROUND PLANE AND BUNNY MATERIAL
# ============================================================
obj_node = hou.node('/obj')
if obj_node:
    for child in obj_node.children():
        type_name = child.type().name().lower()
        child_name = child.name().lower()

        if type_name != 'geo':
            continue

        # --- Ground plane detection ---
        is_ground = any(kw in child_name for kw in ('ground', 'plane', 'floor', 'shadow_catcher', 'shadowcatcher', 'matte', 'catcher'))
        if not is_ground:
            try:
                for sop in child.allSubChildren():
                    sop_type = sop.type().name().lower()
                    sop_name = sop.name().lower()
                    if sop_type in ('grid', 'plane') or any(kw in sop_name for kw in ('ground', 'plane', 'floor', 'grid')):
                        is_ground = True
                        break
            except:
                pass

        if is_ground:
            result['has_ground_plane'] = True
            result['ground_plane_name'] = child.name()
            # Check material assignment on ground plane
            shop_path = child.parm('shop_materialpath')
            if shop_path:
                mat_val = shop_path.eval()
                if mat_val:
                    result['ground_plane_has_material'] = True
                    result['ground_plane_material_path'] = mat_val
            # Also check for material SOP inside
            try:
                for sop in child.allSubChildren():
                    if sop.type().name().lower() == 'material':
                        result['ground_plane_has_material'] = True
                        break
            except:
                pass

        # --- Bunny material check ---
        is_bunny = any(kw in child_name for kw in ('bunny', 'rabbit', 'stanford'))
        if is_bunny:
            shop_path = child.parm('shop_materialpath')
            if shop_path:
                mat_val = shop_path.eval()
                if mat_val:
                    result['bunny_has_material'] = True
                    result['bunny_material_path'] = mat_val
            # Also check for material SOP inside
            try:
                for sop in child.allSubChildren():
                    if sop.type().name().lower() == 'material':
                        mat_parm = sop.parm('shop_materialpath1')
                        if mat_parm and mat_parm.eval():
                            result['bunny_has_material'] = True
                            result['bunny_material_path'] = mat_parm.eval()
                        break
            except:
                pass

# ============================================================
# CHECK /out FOR MANTRA AND PASSES
# ============================================================
out_node = hou.node('/out')
if out_node:
    for child in out_node.children():
        type_name = child.type().name().lower()
        if 'mantra' not in type_name and 'ifd' not in type_name:
            continue

        result['has_mantra_node'] = True
        try:
            vm_picture = child.parm('vm_picture')
            if vm_picture:
                result['mantra_output_path'] = vm_picture.eval()
        except:
            pass

        # Count distinct output paths (separate render passes)
        pass_paths = set()
        try:
            vp = child.parm('vm_picture')
            if vp and vp.eval():
                pass_paths.add(vp.eval())
        except:
            pass

        # Check for extra image planes (deep rasters / AOVs)
        extra_planes = []
        try:
            num_planes = child.parm('vm_numaux')
            if num_planes:
                n = num_planes.eval()
                for i in range(1, int(n) + 1):
                    plane_name_p = child.parm('vm_variable_plane%d' % i)
                    plane_file_p = child.parm('vm_filename_plane%d' % i)
                    plane_name = plane_name_p.eval() if plane_name_p else ''
                    plane_file = plane_file_p.eval() if plane_file_p else ''
                    if plane_name or plane_file:
                        extra_planes.append({'name': plane_name, 'file': plane_file})
                    if plane_file:
                        pass_paths.add(plane_file)
        except:
            pass

        result['extra_image_planes'] = extra_planes
        result['pass_paths'] = list(pass_paths)
        result['pass_count'] = len(pass_paths)
        result['has_separate_passes'] = len(pass_paths) >= 2 or len(extra_planes) >= 1

    # Also check for multiple Mantra nodes (each as a separate pass)
    mantra_nodes = [c for c in out_node.children() if 'mantra' in c.type().name().lower() or 'ifd' in c.type().name().lower()]
    if len(mantra_nodes) >= 2:
        result['has_separate_passes'] = True
        all_paths = set()
        for mn in mantra_nodes:
            try:
                vp = mn.parm('vm_picture')
                if vp and vp.eval():
                    all_paths.add(vp.eval())
            except:
                pass
        if all_paths:
            result['pass_paths'] = list(all_paths)
            result['pass_count'] = len(all_paths)

# ============================================================
# CHECK /img (COP2) NETWORK
# ============================================================
img_node = hou.node('/img')
if img_node:
    cop_nets = img_node.children()
    if cop_nets:
        result['has_cop_network'] = True
        # Explore first COP network (or all of them)
        all_cop_nodes = []
        for cop_net in cop_nets:
            try:
                for cop_child in cop_net.allSubChildren():
                    all_cop_nodes.append(cop_child)
            except:
                pass
            # Also count direct children
            try:
                for cop_child in cop_net.children():
                    all_cop_nodes.append(cop_child)
            except:
                pass

        # Deduplicate by path
        seen_paths = set()
        unique_nodes = []
        for n in all_cop_nodes:
            if n.path() not in seen_paths:
                seen_paths.add(n.path())
                unique_nodes.append(n)

        result['cop_node_count'] = len(unique_nodes)
        result['cop_node_names'] = [n.name() for n in unique_nodes[:20]]
        result['cop_node_types'] = list(set([n.type().name() for n in unique_nodes]))

        for n in unique_nodes:
            n_type = n.type().name().lower()
            n_name = n.name().lower()

            # Check if any file node references bg_plate.jpg
            if n_type in ('file', 'cop2_file', 'image'):
                try:
                    for pname in ('filename1', 'file', 'filename', 'coppath'):
                        p = n.parm(pname)
                        if p:
                            val = p.eval()
                            if val and 'bg_plate' in val:
                                result['cop_references_bg_plate'] = True
                                break
                except:
                    pass

            # Check for composite/merge/over/multiply operations
            if any(kw in n_type for kw in ('over', 'multiply', 'composite', 'merge', 'atop', 'screen', 'add', 'subtract')):
                result['cop_has_composite_op'] = True
            if any(kw in n_name for kw in ('over', 'multiply', 'composite', 'merge', 'comp')):
                result['cop_has_composite_op'] = True

            # Check for output ROP
            if any(kw in n_type for kw in ('rop_comp', 'output', 'rop')):
                result['cop_has_output_rop'] = True

        # If no COP children found in sub-networks, check direct children of /img
        if result['cop_node_count'] == 0:
            direct = img_node.children()
            result['cop_node_count'] = len(direct)
            result['cop_node_names'] = [n.name() for n in direct]
            result['cop_node_types'] = [n.type().name() for n in direct]

print(json.dumps(result))
" 2>/dev/null || echo '{"error": "hython analysis failed"}')
fi

echo "Scene analysis: $SCENE_ANALYSIS"

# ================================================================
# PARSE ANALYSIS RESULTS
# ================================================================
parse_field() {
    echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('$1', '$2'))" 2>/dev/null || echo "$2"
}
parse_bool() {
    echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('$1') else 'false')" 2>/dev/null || echo "false"
}
parse_json_field() {
    echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('$1', $2)))" 2>/dev/null || echo "$2"
}

HAS_SHADOW_CATCHER_MAT=$(parse_bool has_shadow_catcher_material)
SHADOW_CATCHER_MAT_NAME=$(parse_field shadow_catcher_material_name "")
HAS_CHROME_MAT=$(parse_bool has_chrome_material)
CHROME_MAT_NAME=$(parse_field chrome_material_name "")
CHROME_METALLIC=$(parse_field chrome_metallic "0")
CHROME_ROUGHNESS=$(parse_field chrome_roughness "1")
MATERIAL_NAMES=$(parse_json_field material_names "[]")
MATERIAL_TYPES=$(parse_json_field material_types "[]")

HAS_GROUND_PLANE=$(parse_bool has_ground_plane)
GROUND_PLANE_NAME=$(parse_field ground_plane_name "")
GROUND_PLANE_HAS_MAT=$(parse_bool ground_plane_has_material)
GROUND_PLANE_MAT_PATH=$(parse_field ground_plane_material_path "")

BUNNY_HAS_MAT=$(parse_bool bunny_has_material)
BUNNY_MAT_PATH=$(parse_field bunny_material_path "")

HAS_MANTRA=$(parse_bool has_mantra_node)
MANTRA_OUTPUT=$(parse_field mantra_output_path "")
HAS_SEPARATE_PASSES=$(parse_bool has_separate_passes)
PASS_COUNT=$(parse_field pass_count "0")
PASS_PATHS=$(parse_json_field pass_paths "[]")
EXTRA_PLANES=$(parse_json_field extra_image_planes "[]")

HAS_COP_NETWORK=$(parse_bool has_cop_network)
COP_NODE_COUNT=$(parse_field cop_node_count "0")
COP_NODE_NAMES=$(parse_json_field cop_node_names "[]")
COP_NODE_TYPES=$(parse_json_field cop_node_types "[]")
COP_REFS_BG_PLATE=$(parse_bool cop_references_bg_plate)
COP_HAS_COMPOSITE=$(parse_bool cop_has_composite_op)
COP_HAS_OUTPUT_ROP=$(parse_bool cop_has_output_rop)

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

    "has_shadow_catcher_material": $HAS_SHADOW_CATCHER_MAT,
    "shadow_catcher_material_name": "$SHADOW_CATCHER_MAT_NAME",
    "has_chrome_material": $HAS_CHROME_MAT,
    "chrome_material_name": "$CHROME_MAT_NAME",
    "chrome_metallic": $CHROME_METALLIC,
    "chrome_roughness": $CHROME_ROUGHNESS,
    "material_names": $MATERIAL_NAMES,
    "material_types": $MATERIAL_TYPES,

    "has_ground_plane": $HAS_GROUND_PLANE,
    "ground_plane_name": "$GROUND_PLANE_NAME",
    "ground_plane_has_material": $GROUND_PLANE_HAS_MAT,
    "ground_plane_material_path": "$GROUND_PLANE_MAT_PATH",

    "bunny_has_material": $BUNNY_HAS_MAT,
    "bunny_material_path": "$BUNNY_MAT_PATH",

    "has_mantra_node": $HAS_MANTRA,
    "mantra_output_path": "$MANTRA_OUTPUT",
    "has_separate_passes": $HAS_SEPARATE_PASSES,
    "pass_count": $PASS_COUNT,
    "pass_paths": $PASS_PATHS,
    "extra_image_planes": $EXTRA_PLANES,

    "has_cop_network": $HAS_COP_NETWORK,
    "cop_node_count": $COP_NODE_COUNT,
    "cop_node_names": $COP_NODE_NAMES,
    "cop_node_types": $COP_NODE_TYPES,
    "cop_references_bg_plate": $COP_REFS_BG_PLATE,
    "cop_has_composite_op": $COP_HAS_COMPOSITE,
    "cop_has_output_rop": $COP_HAS_OUTPUT_ROP,

    "render_file_count": $RENDER_FILE_COUNT,
    "render_files": $RENDER_FILES,
    "composite_exists": $COMPOSITE_EXISTS,
    "composite_size_bytes": $COMPOSITE_SIZE,

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
