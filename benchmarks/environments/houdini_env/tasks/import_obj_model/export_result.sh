#!/bin/bash
echo "=== Exporting import_obj_model result ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_HIPNC="/home/ga/HoudiniProjects/imported_bunny.hipnc"
OBJ_PATH="/home/ga/HoudiniProjects/data/bunny.obj"
HFS_DIR=$(get_hfs_dir)

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
IS_VALID_HIPNC="false"
FILE_CREATED="false"

if [ -f "$OUTPUT_HIPNC" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_HIPNC" 2>/dev/null || echo "0")
    FILE_CREATED="true"

    # Check magic bytes for Houdini file
    MAGIC=$(head -c 8 "$OUTPUT_HIPNC" 2>/dev/null | strings | head -1)
    if echo "$MAGIC" | grep -q "HouLC\|Houdini"; then
        IS_VALID_HIPNC="true"
    elif [ "$OUTPUT_SIZE" -gt 1000 ]; then
        IS_VALID_HIPNC="true"
    fi
fi

# ================================================================
# ANALYZE SCENE WITH HYTHON
# ================================================================
SCENE_ANALYSIS=""
HAS_GEO_NODE="false"
HAS_FILE_SOP="false"
FILE_SOP_PATH=""
NODE_COUNT="0"
GEO_NODE_CHILDREN="[]"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    SCENE_ANALYSIS=$("$HFS_DIR/bin/hython" -c "
import hou
import json

hou.hipFile.load('$OUTPUT_HIPNC')

obj_nodes = hou.node('/obj').children()
result = {
    'node_count': len(obj_nodes),
    'has_geo_node': False,
    'has_file_sop': False,
    'file_sop_path': '',
    'file_sop_references_obj': False,
    'geo_node_children': [],
    'all_nodes': [],
}

for node in obj_nodes:
    node_info = {'name': node.name(), 'type': node.type().name()}
    result['all_nodes'].append(node_info)

    if node.type().name() == 'geo':
        result['has_geo_node'] = True
        for child in node.children():
            child_info = {'name': child.name(), 'type': child.type().name()}
            result['geo_node_children'].append(child_info)

            if child.type().name() == 'file':
                result['has_file_sop'] = True
                file_path = child.parm('file').eval()
                result['file_sop_path'] = file_path
                if 'bunny' in file_path.lower() or file_path.endswith('.obj'):
                    result['file_sop_references_obj'] = True

print(json.dumps(result))
" 2>/dev/null || echo '{"error": "hython failed"}')

    if [ -n "$SCENE_ANALYSIS" ]; then
        HAS_GEO_NODE=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_geo_node') else 'false')" 2>/dev/null || echo "false")
        HAS_FILE_SOP=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('has_file_sop') else 'false')" 2>/dev/null || echo "false")
        FILE_SOP_PATH=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('file_sop_path', ''))" 2>/dev/null || echo "")
        NODE_COUNT=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('node_count', 0))" 2>/dev/null || echo "0")
        GEO_NODE_CHILDREN=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('geo_node_children', [])))" 2>/dev/null || echo "[]")
    fi
fi

# ================================================================
# CHECK FILE SOP REFERENCES BUNNY
# ================================================================
FILE_REFERENCES_BUNNY="false"
if [ -n "$FILE_SOP_PATH" ]; then
    if echo "$FILE_SOP_PATH" | grep -qi "bunny\|\.obj"; then
        FILE_REFERENCES_BUNNY="true"
    fi
fi

# ================================================================
# CHECK HOUDINI STATE
# ================================================================
HOUDINI_RUNNING="false"
HOUDINI_WINDOW_TITLE=""

if is_houdini_running | grep -q "true"; then
    HOUDINI_RUNNING="true"
fi

HOUDINI_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "houdini\|\.hipnc\|\.hip" || echo "")
if [ -n "$HOUDINI_WINDOWS" ]; then
    HOUDINI_WINDOW_TITLE=$(echo "$HOUDINI_WINDOWS" | head -1 | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}')
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_HIPNC",
    "is_valid_hipnc": $IS_VALID_HIPNC,
    "file_created": $FILE_CREATED,
    "has_geo_node": $HAS_GEO_NODE,
    "has_file_sop": $HAS_FILE_SOP,
    "file_sop_path": "$FILE_SOP_PATH",
    "file_references_bunny": $FILE_REFERENCES_BUNNY,
    "node_count": $NODE_COUNT,
    "geo_node_children": $GEO_NODE_CHILDREN,
    "houdini_was_running": $HOUDINI_RUNNING,
    "houdini_window_title": "$HOUDINI_WINDOW_TITLE",
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
