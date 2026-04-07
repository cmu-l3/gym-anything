#!/bin/bash
echo "=== Exporting procedural_building_hda result ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# Take final screenshot
take_screenshot /tmp/task_end.png

HDA_PATH="/home/ga/HoudiniProjects/hda/procedural_building.hda"
OUTPUT_SCENE="/home/ga/HoudiniProjects/building_test.hipnc"
HFS_DIR=$(get_hfs_dir)

# ================================================================
# CHECK HDA FILE
# ================================================================
HDA_EXISTS="false"
HDA_SIZE="0"

if [ -f "$HDA_PATH" ]; then
    HDA_EXISTS="true"
    HDA_SIZE=$(stat -c%s "$HDA_PATH" 2>/dev/null || echo "0")
fi

# ================================================================
# CHECK TEST SCENE FILE
# ================================================================
SCENE_EXISTS="false"
SCENE_SIZE="0"

if [ -f "$OUTPUT_SCENE" ]; then
    SCENE_EXISTS="true"
    SCENE_SIZE=$(stat -c%s "$OUTPUT_SCENE" 2>/dev/null || echo "0")
fi

# ================================================================
# ANALYZE HDA AND SCENE WITH HYTHON
# ================================================================
ANALYSIS='{"error": "hython not run"}'

if [ "$HDA_EXISTS" = "true" ] || [ "$SCENE_EXISTS" = "true" ]; then
    ANALYSIS=$("$HFS_DIR/bin/hython" -c "
import hou
import json

result = {
    'hda_valid': False,
    'hda_installs': False,
    'hda_definition_count': 0,
    'hda_operator_name': '',
    'has_building_width': False,
    'has_building_height': False,
    'has_num_floors': False,
    'has_window_density': False,
    'param_defaults': {},
    'param_ranges': {},
    'all_param_names': [],
    'default_poly_count': 0,
    'default_has_uvs': False,
    'default_geo_height': 0.0,
    'scene_exists': False,
    'instance_count': 0,
    'instance_params': [],
    'instance_poly_counts': [],
    'instance_geo_heights': [],
    'poly_count_varies_with_floors': False,
    'height_varies_with_param': False,
}

hda_path = '$HDA_PATH'
scene_path = '$OUTPUT_SCENE'

# ============================================================
# PART 1: Analyze the HDA file
# ============================================================
import os
if os.path.isfile(hda_path):
    try:
        hou.hda.installFile(hda_path)
        result['hda_installs'] = True

        defs = hou.hda.definitionsInFile(hda_path)
        result['hda_definition_count'] = len(defs)

        if len(defs) > 0:
            result['hda_valid'] = True
            hda_def = defs[0]
            result['hda_operator_name'] = hda_def.nodeTypeName()

            # Inspect parameter template group
            ptg = hda_def.parmTemplateGroup()
            all_parm_names = []

            def collect_parms(group_or_folder):
                for pt in group_or_folder.parmTemplates():
                    if pt.type() == hou.parmTemplateType.Folder:
                        collect_parms(pt)
                    else:
                        all_parm_names.append(pt.name())

            collect_parms(ptg)
            result['all_param_names'] = all_parm_names

            # Check required parameters
            for parm_name in ['building_width', 'building_height', 'num_floors', 'window_density']:
                pt = ptg.find(parm_name)
                if pt is not None:
                    result['has_' + parm_name] = True
                    # Get default value
                    try:
                        dv = pt.defaultValue()
                        if isinstance(dv, tuple):
                            result['param_defaults'][parm_name] = dv[0]
                        else:
                            result['param_defaults'][parm_name] = dv
                    except:
                        pass
                    # Get range
                    try:
                        mn = pt.minValue()
                        mx = pt.maxValue()
                        result['param_ranges'][parm_name] = [mn, mx]
                    except:
                        pass

            # ============================================================
            # Create a temporary instance to measure default geometry
            # ============================================================
            try:
                obj = hou.node('/obj')
                test_geo = obj.createNode('geo', 'hda_test_container')
                # Determine if this is SOP or OBJ level
                node_type_cat = hda_def.nodeTypeCategory().name()
                if node_type_cat == 'Sop':
                    # Delete default file node if present
                    for ch in test_geo.children():
                        ch.destroy()
                    hda_node = test_geo.createNode(hda_def.nodeTypeName())
                else:
                    # OBJ-level asset
                    hda_node = obj.createNode(hda_def.nodeTypeName(), 'hda_test_obj')
                    test_geo = None

                if hda_node:
                    hda_node.cook(force=True)
                    geo = hda_node.geometry()
                    if geo is None and hda_node.children():
                        # Try to get geometry from display node
                        display = hda_node.displayNode()
                        if display:
                            geo = display.geometry()
                    if geo:
                        result['default_poly_count'] = len(geo.prims())
                        uv_attr = geo.findVertexAttrib('uv') or geo.findPointAttrib('uv')
                        result['default_has_uvs'] = uv_attr is not None
                        bb = geo.boundingBox()
                        result['default_geo_height'] = bb.maxvec()[1] - bb.minvec()[1]

                    # Test polygon count variation with different num_floors
                    poly_counts_by_floors = {}
                    if hda_node.parm('num_floors'):
                        for nf in [3, 7, 15]:
                            hda_node.parm('num_floors').set(nf)
                            hda_node.cook(force=True)
                            g = hda_node.geometry()
                            if g is None and hda_node.children():
                                d = hda_node.displayNode()
                                if d:
                                    g = d.geometry()
                            if g:
                                poly_counts_by_floors[nf] = len(g.prims())
                        vals = list(poly_counts_by_floors.values())
                        if len(vals) >= 2 and len(set(vals)) > 1:
                            result['poly_count_varies_with_floors'] = True

                    # Test height variation with building_height parameter
                    heights_by_param = {}
                    if hda_node.parm('building_height'):
                        # Reset num_floors first
                        if hda_node.parm('num_floors'):
                            hda_node.parm('num_floors').set(5)
                        for bh in [20.0, 50.0, 100.0]:
                            hda_node.parm('building_height').set(bh)
                            hda_node.cook(force=True)
                            g = hda_node.geometry()
                            if g is None and hda_node.children():
                                d = hda_node.displayNode()
                                if d:
                                    g = d.geometry()
                            if g:
                                bb2 = g.boundingBox()
                                heights_by_param[bh] = bb2.maxvec()[1] - bb2.minvec()[1]
                        vals = list(heights_by_param.values())
                        if len(vals) >= 2 and max(vals) - min(vals) > 1.0:
                            result['height_varies_with_param'] = True

                    # Clean up
                    if test_geo:
                        test_geo.destroy()
                    elif hda_node:
                        hda_node.destroy()
            except Exception as e:
                result['hda_instance_error'] = str(e)
    except Exception as e:
        result['hda_install_error'] = str(e)

# ============================================================
# PART 2: Analyze the test scene
# ============================================================
if os.path.isfile(scene_path):
    result['scene_exists'] = True
    try:
        hou.hipFile.load(scene_path)

        # Re-install HDA in case it is needed
        if os.path.isfile(hda_path):
            try:
                hou.hda.installFile(hda_path)
            except:
                pass

        # Find all instances of the procedural_building HDA in the scene
        obj_node = hou.node('/obj')
        instances = []

        if obj_node:
            for child in obj_node.allSubChildren():
                type_name = child.type().name().lower()
                if 'procedural_building' in type_name:
                    inst = {'name': child.path(), 'params': {}}
                    for pn in ['building_width', 'building_height', 'num_floors', 'window_density']:
                        p = child.parm(pn)
                        if p:
                            inst['params'][pn] = p.eval()
                    # Get poly count and height
                    try:
                        child.cook(force=True)
                        g = child.geometry()
                        if g is None and child.children():
                            d = child.displayNode()
                            if d:
                                g = d.geometry()
                        if g:
                            inst['poly_count'] = len(g.prims())
                            bb = g.boundingBox()
                            inst['geo_height'] = bb.maxvec()[1] - bb.minvec()[1]
                    except:
                        inst['poly_count'] = 0
                        inst['geo_height'] = 0.0
                    instances.append(inst)

            # Also check for HDA instances inside geo nodes
            if len(instances) == 0:
                for child in obj_node.children():
                    if child.type().name() == 'geo':
                        for sop in child.allSubChildren():
                            sop_type = sop.type().name().lower()
                            if 'procedural_building' in sop_type:
                                inst = {'name': sop.path(), 'params': {}}
                                for pn in ['building_width', 'building_height', 'num_floors', 'window_density']:
                                    p = sop.parm(pn)
                                    if p:
                                        inst['params'][pn] = p.eval()
                                try:
                                    sop.cook(force=True)
                                    g = sop.geometry()
                                    if g:
                                        inst['poly_count'] = len(g.prims())
                                        bb = g.boundingBox()
                                        inst['geo_height'] = bb.maxvec()[1] - bb.minvec()[1]
                                except:
                                    inst['poly_count'] = 0
                                    inst['geo_height'] = 0.0
                                instances.append(inst)

        result['instance_count'] = len(instances)
        result['instance_params'] = [inst.get('params', {}) for inst in instances]
        result['instance_poly_counts'] = [inst.get('poly_count', 0) for inst in instances]
        result['instance_geo_heights'] = [inst.get('geo_height', 0.0) for inst in instances]

    except Exception as e:
        result['scene_load_error'] = str(e)

print(json.dumps(result))
" 2>/dev/null || echo '{"error": "hython analysis failed"}')
fi

echo "Analysis output: $ANALYSIS"

# ================================================================
# PARSE ANALYSIS RESULTS INTO SHELL VARIABLES
# ================================================================
parse_field() {
    echo "$ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print(json.dumps(d.get('$1', $2)))" 2>/dev/null || echo "$2"
}

parse_bool() {
    echo "$ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('$1') else 'false')" 2>/dev/null || echo "false"
}

HDA_VALID=$(parse_bool "hda_valid")
HDA_INSTALLS=$(parse_bool "hda_installs")
HDA_DEF_COUNT=$(parse_field "hda_definition_count" "0")
HDA_OPERATOR=$(echo "$ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('hda_operator_name', ''))" 2>/dev/null || echo "")
HAS_BUILDING_WIDTH=$(parse_bool "has_building_width")
HAS_BUILDING_HEIGHT=$(parse_bool "has_building_height")
HAS_NUM_FLOORS=$(parse_bool "has_num_floors")
HAS_WINDOW_DENSITY=$(parse_bool "has_window_density")
ALL_PARAM_NAMES=$(parse_field "all_param_names" "[]")
PARAM_DEFAULTS=$(parse_field "param_defaults" "{}")
PARAM_RANGES=$(parse_field "param_ranges" "{}")
DEFAULT_POLY_COUNT=$(parse_field "default_poly_count" "0")
DEFAULT_HAS_UVS=$(parse_bool "default_has_uvs")
DEFAULT_GEO_HEIGHT=$(parse_field "default_geo_height" "0.0")
SCENE_FOUND=$(parse_bool "scene_exists")
INSTANCE_COUNT=$(parse_field "instance_count" "0")
INSTANCE_PARAMS=$(parse_field "instance_params" "[]")
INSTANCE_POLY_COUNTS=$(parse_field "instance_poly_counts" "[]")
INSTANCE_GEO_HEIGHTS=$(parse_field "instance_geo_heights" "[]")
POLY_COUNT_VARIES=$(parse_bool "poly_count_varies_with_floors")
HEIGHT_VARIES=$(parse_bool "height_varies_with_param")

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
    "hda_exists": $HDA_EXISTS,
    "hda_size_bytes": $HDA_SIZE,
    "hda_valid": $HDA_VALID,
    "hda_installs": $HDA_INSTALLS,
    "hda_definition_count": $HDA_DEF_COUNT,
    "hda_operator_name": "$HDA_OPERATOR",
    "has_building_width": $HAS_BUILDING_WIDTH,
    "has_building_height": $HAS_BUILDING_HEIGHT,
    "has_num_floors": $HAS_NUM_FLOORS,
    "has_window_density": $HAS_WINDOW_DENSITY,
    "all_param_names": $ALL_PARAM_NAMES,
    "param_defaults": $PARAM_DEFAULTS,
    "param_ranges": $PARAM_RANGES,
    "default_poly_count": $DEFAULT_POLY_COUNT,
    "default_has_uvs": $DEFAULT_HAS_UVS,
    "default_geo_height": $DEFAULT_GEO_HEIGHT,
    "scene_exists": $SCENE_FOUND,
    "scene_size_bytes": $SCENE_SIZE,
    "instance_count": $INSTANCE_COUNT,
    "instance_params": $INSTANCE_PARAMS,
    "instance_poly_counts": $INSTANCE_POLY_COUNTS,
    "instance_geo_heights": $INSTANCE_GEO_HEIGHTS,
    "poly_count_varies_with_floors": $POLY_COUNT_VARIES,
    "height_varies_with_param": $HEIGHT_VARIES,
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
