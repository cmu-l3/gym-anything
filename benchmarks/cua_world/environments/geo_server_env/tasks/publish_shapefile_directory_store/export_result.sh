#!/bin/bash
echo "=== Exporting publish_shapefile_directory_store result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# 1. Verify Workspace 'shp_ne'
EXPECTED_WS="shp_ne"
WS_FOUND="false"
WS_URI=""

WS_STATUS=$(gs_rest_status "workspaces/${EXPECTED_WS}.json")
if [ "$WS_STATUS" = "200" ]; then
    WS_FOUND="true"
    WS_URI=$(gs_rest_get "namespaces/${EXPECTED_WS}.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('namespace',{}).get('uri',''))" 2>/dev/null || echo "")
fi

# 2. Verify Datastore 'shp_directory' in 'shp_ne'
EXPECTED_STORE="shp_directory"
STORE_FOUND="false"
STORE_TYPE=""
STORE_CONN=""

STORE_STATUS=$(gs_rest_status "workspaces/${EXPECTED_WS}/datastores/${EXPECTED_STORE}.json")
if [ "$STORE_STATUS" = "200" ]; then
    STORE_DATA=$(gs_rest_get "workspaces/${EXPECTED_WS}/datastores/${EXPECTED_STORE}.json")
    STORE_FOUND="true"
    STORE_TYPE=$(echo "$STORE_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dataStore',{}).get('type',''))" 2>/dev/null || echo "")
    # Check connection parameters to verify it points to a file/directory
    STORE_CONN=$(echo "$STORE_DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin)
cp = d.get('dataStore', {}).get('connectionParameters', {}).get('entry', [])
if not isinstance(cp, list): cp = [cp]
for entry in cp:
    if entry.get('@key') == 'url':
        print(entry.get('$'))
" 2>/dev/null || echo "")
fi

# 3. Verify Layers
LAYERS_PUBLISHED=0
COUNTRIES_FOUND="false"
LAKES_FOUND="false"

# Check Countries
COUNTRIES_STATUS=$(gs_rest_status "workspaces/${EXPECTED_WS}/datastores/${EXPECTED_STORE}/featuretypes/ne_110m_admin_0_countries.json")
if [ "$COUNTRIES_STATUS" = "200" ]; then
    COUNTRIES_FOUND="true"
    LAYERS_PUBLISHED=$((LAYERS_PUBLISHED + 1))
fi

# Check Lakes
LAKES_STATUS=$(gs_rest_status "workspaces/${EXPECTED_WS}/datastores/${EXPECTED_STORE}/featuretypes/ne_110m_lakes.json")
if [ "$LAKES_STATUS" = "200" ]; then
    LAKES_FOUND="true"
    LAYERS_PUBLISHED=$((LAYERS_PUBLISHED + 1))
fi

# 4. Verify Files in Container
FILES_IN_CONTAINER="false"
FILE_CHECK=$(docker exec gs-app ls -1 /opt/geoserver/data_dir/shp_data/ne_110m_admin_0_countries.shp 2>/dev/null || echo "")
if [ -n "$FILE_CHECK" ]; then
    FILES_IN_CONTAINER="true"
fi

# 5. Verify Output Images
COUNTRIES_IMG="/home/ga/countries_map.png"
LAKES_IMG="/home/ga/lakes_map.png"
COUNTRIES_IMG_EXISTS="false"
LAKES_IMG_EXISTS="false"
COUNTRIES_IMG_SIZE=0
LAKES_IMG_SIZE=0

if [ -f "$COUNTRIES_IMG" ]; then
    COUNTRIES_IMG_EXISTS="true"
    COUNTRIES_IMG_SIZE=$(stat -c %s "$COUNTRIES_IMG")
fi
if [ -f "$LAKES_IMG" ]; then
    LAKES_IMG_EXISTS="true"
    LAKES_IMG_SIZE=$(stat -c %s "$LAKES_IMG")
fi

# 6. Check GUI interaction
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "workspace_found": ${WS_FOUND},
    "workspace_uri": "$(json_escape "$WS_URI")",
    "store_found": ${STORE_FOUND},
    "store_type": "$(json_escape "$STORE_TYPE")",
    "store_connection": "$(json_escape "$STORE_CONN")",
    "countries_layer_found": ${COUNTRIES_FOUND},
    "lakes_layer_found": ${LAKES_FOUND},
    "files_in_container": ${FILES_IN_CONTAINER},
    "countries_image_exists": ${COUNTRIES_IMG_EXISTS},
    "countries_image_size": ${COUNTRIES_IMG_SIZE},
    "lakes_image_exists": ${LAKES_IMG_EXISTS},
    "lakes_image_size": ${LAKES_IMG_SIZE},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/publish_shp_dir_result.json"

echo "=== Export complete ==="