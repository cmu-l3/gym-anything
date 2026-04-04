#!/bin/bash
echo "=== Exporting configure_dedicated_blobstore result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_DIR="/home/ga/geoserver/cache/countries"
EXPECTED_STORE="countries_store"
LAYER_NAME="ne:ne_countries"

# 1. Verify Directory and Tiles on Disk
DIR_EXISTS="false"
TILE_COUNT=0
TILES_CREATED_DURING_TASK="false"
CACHED_GRIDSETS=""

if [ -d "$TARGET_DIR" ]; then
    DIR_EXISTS="true"
    # Count files (tiles are usually images or metatiles)
    # GWC structure: layer_name/gridset_name/zoom/x_y.ext
    TILE_COUNT=$(find "$TARGET_DIR" -type f | wc -l)
    
    # Check timestamps of files
    NEW_FILES=$(find "$TARGET_DIR" -type f -newermt "@$TASK_START" | wc -l)
    if [ "$NEW_FILES" -gt 0 ]; then
        TILES_CREATED_DURING_TASK="true"
    fi
    
    # List subdirectories to identify gridsets (e.g., EPSG_4326)
    CACHED_GRIDSETS=$(ls "$TARGET_DIR" 2>/dev/null | grep -v "\." | tr '\n' ',' || echo "")
fi

# 2. Verify BlobStore Configuration via REST API
# GeoWebCache REST API is usually at /geoserver/gwc/rest/
# Note: GWC REST often requires strictly correct Accept headers or .xml extension
STORE_CONFIG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$GS_AUTH" "${GS_URL}/gwc/rest/blobstores/${EXPECTED_STORE}")
STORE_CONFIG_XML=""
STORE_PATH_CONFIGURED=""

if [ "$STORE_CONFIG_STATUS" = "200" ]; then
    STORE_CONFIG_XML=$(curl -s -u "$GS_AUTH" "${GS_URL}/gwc/rest/blobstores/${EXPECTED_STORE}")
    # Extract baseDirectory using simple grep/sed as it's XML
    STORE_PATH_CONFIGURED=$(echo "$STORE_CONFIG_XML" | grep -oP '(?<=<baseDirectory>).*?(?=</baseDirectory>)' || echo "")
fi

# 3. Verify Layer Assignment
# GET /geoserver/gwc/rest/layers/ne:ne_countries.xml
LAYER_CONFIG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$GS_AUTH" "${GS_URL}/gwc/rest/layers/${LAYER_NAME}")
LAYER_BLOBSTORE=""

if [ "$LAYER_CONFIG_STATUS" = "200" ]; then
    LAYER_XML=$(curl -s -u "$GS_AUTH" "${GS_URL}/gwc/rest/layers/${LAYER_NAME}")
    LAYER_BLOBSTORE=$(echo "$LAYER_XML" | grep -oP '(?<=<blobStoreId>).*?(?=</blobStoreId>)' || echo "default")
fi

# 4. Check for GUI interaction
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "directory_exists": $DIR_EXISTS,
    "tile_count": $TILE_COUNT,
    "tiles_created_during_task": $TILES_CREATED_DURING_TASK,
    "cached_gridsets": "$(json_escape "$CACHED_GRIDSETS")",
    "store_exists_api": $([ "$STORE_CONFIG_STATUS" = "200" ] && echo "true" || echo "false"),
    "store_path_configured": "$(json_escape "$STORE_PATH_CONFIGURED")",
    "layer_blobstore_assigned": "$(json_escape "$LAYER_BLOBSTORE")",
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_dedicated_blobstore_result.json"

echo "=== Export complete ==="