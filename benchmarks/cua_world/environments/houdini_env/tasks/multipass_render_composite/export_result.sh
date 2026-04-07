#!/bin/bash
echo "=== Exporting multipass_render_composite result ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_SCENE="/home/ga/HoudiniProjects/multipass_composite.hipnc"
RENDER_DIR="/home/ga/HoudiniProjects/renders/passes"
COMPOSITE_PATH="/home/ga/HoudiniProjects/renders/final_composite.exr"
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
# CHECK RENDERED PASS FILES
# ================================================================
PASS_FILES_COUNT=0
PASS_FILES_LIST="[]"

if [ -d "$RENDER_DIR" ]; then
    PASS_FILES=$(find "$RENDER_DIR" -name "*.exr" -type f 2>/dev/null)
    if [ -n "$PASS_FILES" ]; then
        PASS_FILES_COUNT=$(echo "$PASS_FILES" | wc -l)
        PASS_FILES_LIST=$(echo "$PASS_FILES" | python3 -c "import sys, json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))" 2>/dev/null || echo "[]")
    fi
fi

# ================================================================
# CHECK FINAL COMPOSITE
# ================================================================
COMPOSITE_EXISTS="false"
COMPOSITE_SIZE="0"

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
    'mantra_node_found': False,
    'mantra_node_name': '',
    'num_extra_planes': 0,
    'extra_plane_variables': [],
    'extra_plane_details': [],
    'cop_network_exists': False,
    'cop_node_count': 0,
    'cop_node_names': [],
    'cop_node_types': [],
    'cop_has_file_nodes': False,
    'cop_file_node_count': 0,
    'cop_has_merge_or_composite': False,
    'cop_has_rop_output': False,
    'vm_picture': '',
}

# -----------------------------------------------------------
# Check /out for Mantra nodes and extra image planes
# -----------------------------------------------------------
out_node = hou.node('/out')
if out_node:
    for child in out_node.children():
        type_name = child.type().name()
        if type_name == 'ifd' or 'mantra' in type_name.lower():
            result['mantra_node_found'] = True
            result['mantra_node_name'] = child.name()

            # Get vm_picture
            vm_pic = child.parm('vm_picture')
            if vm_pic:
                result['vm_picture'] = vm_pic.eval()

            # Get number of extra image planes
            vm_numaux = child.parm('vm_numaux')
            if vm_numaux:
                num_planes = vm_numaux.eval()
                result['num_extra_planes'] = num_planes

                # Iterate through each extra plane
                for i in range(1, num_planes + 1):
                    plane_info = {}

                    # Variable name (the VEX variable / AOV name)
                    var_parm = child.parm('vm_variable_plane{}'.format(i))
                    if var_parm:
                        var_name = var_parm.eval()
                        plane_info['variable'] = var_name
                        result['extra_plane_variables'].append(var_name)

                    # VEX type
                    vextype_parm = child.parm('vm_vextype_plane{}'.format(i))
                    if vextype_parm:
                        plane_info['vextype'] = vextype_parm.eval()

                    # Channel name
                    channel_parm = child.parm('vm_channel_plane{}'.format(i))
                    if channel_parm:
                        plane_info['channel'] = channel_parm.eval()

                    # Light export mode
                    lightexport_parm = child.parm('vm_lightexport{}'.format(i))
                    if lightexport_parm:
                        plane_info['lightexport'] = lightexport_parm.eval()

                    # Filename
                    filename_parm = child.parm('vm_filename_plane{}'.format(i))
                    if filename_parm:
                        plane_info['filename'] = filename_parm.eval()

                    result['extra_plane_details'].append(plane_info)

            break  # Only need first Mantra node

# -----------------------------------------------------------
# Check /img COP2 network
# -----------------------------------------------------------
img_node = hou.node('/img')
if img_node:
    result['cop_network_exists'] = True
    cop_children = img_node.allSubChildren()

    # If /img itself has children, great; otherwise check sub-networks
    direct_children = img_node.children()
    if direct_children:
        # There might be a cop2net inside /img, or nodes directly in /img
        all_cop_nodes = []
        for child in img_node.allSubChildren():
            all_cop_nodes.append(child)

        result['cop_node_count'] = len(all_cop_nodes)
        result['cop_node_names'] = [n.name() for n in all_cop_nodes]
        result['cop_node_types'] = [n.type().name() for n in all_cop_nodes]

        # Check for file COP nodes (loading passes)
        file_count = 0
        for n in all_cop_nodes:
            tname = n.type().name().lower()
            if tname == 'file' or tname == 'cop2_file' or 'file' in tname:
                file_count += 1
        result['cop_file_node_count'] = file_count
        result['cop_has_file_nodes'] = file_count > 0

        # Check for merge/composite/add nodes
        for n in all_cop_nodes:
            tname = n.type().name().lower()
            if tname in ('merge', 'composite', 'add', 'over', 'multiply', 'screen', 'vopcop2gen', 'channelcopy'):
                result['cop_has_merge_or_composite'] = True
                break

        # Check for ROP output (rop_comp, composite)
        for n in all_cop_nodes:
            tname = n.type().name().lower()
            if tname in ('rop_comp', 'composite', 'rop_file', 'cop2_rop'):
                result['cop_has_rop_output'] = True
                break
    else:
        result['cop_node_count'] = 0
else:
    # Also check for /img as a COP2 network created differently
    for node in hou.node('/').children():
        if node.type().name() == 'cop2net' or node.type().name() == 'img':
            result['cop_network_exists'] = True
            all_cop_nodes = list(node.allSubChildren())
            result['cop_node_count'] = len(all_cop_nodes)
            result['cop_node_names'] = [n.name() for n in all_cop_nodes]
            result['cop_node_types'] = [n.type().name() for n in all_cop_nodes]

            file_count = 0
            for n in all_cop_nodes:
                tname = n.type().name().lower()
                if 'file' in tname:
                    file_count += 1
            result['cop_file_node_count'] = file_count
            result['cop_has_file_nodes'] = file_count > 0

            for n in all_cop_nodes:
                tname = n.type().name().lower()
                if tname in ('merge', 'composite', 'add', 'over', 'multiply', 'screen', 'vopcop2gen', 'channelcopy'):
                    result['cop_has_merge_or_composite'] = True
                    break

            for n in all_cop_nodes:
                tname = n.type().name().lower()
                if tname in ('rop_comp', 'composite', 'rop_file', 'cop2_rop'):
                    result['cop_has_rop_output'] = True
                    break
            break

print(json.dumps(result))
" 2>/dev/null || echo '{"error": "hython analysis failed"}')
fi

echo "Scene analysis: $SCENE_ANALYSIS"

# ================================================================
# PARSE HYTHON OUTPUT INTO SHELL VARIABLES
# ================================================================
MANTRA_FOUND=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('mantra_node_found') else 'false')" 2>/dev/null || echo "false")
NUM_EXTRA_PLANES=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('num_extra_planes', 0))" 2>/dev/null || echo "0")
EXTRA_PLANE_VARS=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('extra_plane_variables', [])))" 2>/dev/null || echo "[]")
EXTRA_PLANE_DETAILS=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('extra_plane_details', [])))" 2>/dev/null || echo "[]")
COP_EXISTS=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('cop_network_exists') else 'false')" 2>/dev/null || echo "false")
COP_NODE_COUNT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('cop_node_count', 0))" 2>/dev/null || echo "0")
COP_NODE_NAMES=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('cop_node_names', [])))" 2>/dev/null || echo "[]")
COP_NODE_TYPES=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('cop_node_types', [])))" 2>/dev/null || echo "[]")
COP_HAS_FILE=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('cop_has_file_nodes') else 'false')" 2>/dev/null || echo "false")
COP_FILE_COUNT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('cop_file_node_count', 0))" 2>/dev/null || echo "0")
COP_HAS_MERGE=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('cop_has_merge_or_composite') else 'false')" 2>/dev/null || echo "false")
COP_HAS_ROP=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('cop_has_rop_output') else 'false')" 2>/dev/null || echo "false")

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
    "mantra_node_found": $MANTRA_FOUND,
    "num_extra_planes": $NUM_EXTRA_PLANES,
    "extra_plane_variables": $EXTRA_PLANE_VARS,
    "extra_plane_details": $EXTRA_PLANE_DETAILS,
    "cop_network_exists": $COP_EXISTS,
    "cop_node_count": $COP_NODE_COUNT,
    "cop_node_names": $COP_NODE_NAMES,
    "cop_node_types": $COP_NODE_TYPES,
    "cop_has_file_nodes": $COP_HAS_FILE,
    "cop_file_node_count": $COP_FILE_COUNT,
    "cop_has_merge_or_composite": $COP_HAS_MERGE,
    "cop_has_rop_output": $COP_HAS_ROP,
    "pass_files_count": $PASS_FILES_COUNT,
    "pass_files": $PASS_FILES_LIST,
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
