#!/bin/bash
echo "=== Exporting create_custom_gridset result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# GWC REST API Base URL
GWC_REST="${GS_URL}/gwc/rest"

# 1. Check if the Gridset exists
GRIDSET_NAME="EPSG3035_Europe"
GRIDSET_EXISTS="false"
GRIDSET_SRS=""
GRIDSET_TILE_WIDTH="0"
GRIDSET_TILE_HEIGHT="0"
GRIDSET_MIN_X=""
GRIDSET_MIN_Y=""
GRIDSET_MAX_X=""
GRIDSET_MAX_Y=""
GRIDSET_ZOOM_LEVELS="0"

# Fetch Gridset details (GWC often prefers XML, sometimes JSON support is limited for details)
# We will fetch XML and parse it or grep it since GWC JSON response structures can vary by version.
GRIDSET_XML=$(curl -s -u "$GS_AUTH" -H "Accept: application/xml" "${GWC_REST}/gridsets/${GRIDSET_NAME}" 2>/dev/null)

# Check if response is valid XML (contains <gridSet>)
if echo "$GRIDSET_XML" | grep -q "<gridSet>"; then
    GRIDSET_EXISTS="true"
    
    # Extract SRS (e.g., <srs><number>3035</number></srs>)
    SRS_NUM=$(echo "$GRIDSET_XML" | grep -oP "(?<=<srs><number>)[^<]+" || echo "")
    if [ -n "$SRS_NUM" ]; then
        GRIDSET_SRS="EPSG:${SRS_NUM}"
    fi
    
    # Extract Tile Size
    GRIDSET_TILE_WIDTH=$(echo "$GRIDSET_XML" | grep -oP "(?<=<tileWidth>)[^<]+" || echo "0")
    GRIDSET_TILE_HEIGHT=$(echo "$GRIDSET_XML" | grep -oP "(?<=<tileHeight>)[^<]+" || echo "0")
    
    # Extract Bounds (coords)
    GRIDSET_MIN_X=$(echo "$GRIDSET_XML" | grep -oP "(?<=<minX>)[^<]+" || echo "")
    GRIDSET_MIN_Y=$(echo "$GRIDSET_XML" | grep -oP "(?<=<minY>)[^<]+" || echo "")
    GRIDSET_MAX_X=$(echo "$GRIDSET_XML" | grep -oP "(?<=<maxX>)[^<]+" || echo "")
    GRIDSET_MAX_Y=$(echo "$GRIDSET_XML" | grep -oP "(?<=<maxY>)[^<]+" || echo "")
    
    # Count zoom levels (resolutions)
    GRIDSET_ZOOM_LEVELS=$(echo "$GRIDSET_XML" | grep -o "<resolution>" | wc -l)
fi

# 2. Check if Layer is configured to use this Gridset
LAYER_NAME="ne:ne_countries"
LAYER_CONFIGURED="false"

# Fetch Layer GWC config
LAYER_XML=$(curl -s -u "$GS_AUTH" -H "Accept: application/xml" "${GWC_REST}/layers/${LAYER_NAME}" 2>/dev/null)

if echo "$LAYER_XML" | grep -q "<GeoServerLayer>"; then
    # Check if the gridset name appears in the gridSubsets
    if echo "$LAYER_XML" | grep -q "<gridSetName>${GRIDSET_NAME}</gridSetName>"; then
        LAYER_CONFIGURED="true"
    fi
fi

# 3. Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "gridset_exists": ${GRIDSET_EXISTS},
    "gridset_name": "$(json_escape "$GRIDSET_NAME")",
    "gridset_srs": "$(json_escape "$GRIDSET_SRS")",
    "tile_width": ${GRIDSET_TILE_WIDTH},
    "tile_height": ${GRIDSET_TILE_HEIGHT},
    "bounds": {
        "minx": "$(json_escape "$GRIDSET_MIN_X")",
        "miny": "$(json_escape "$GRIDSET_MIN_Y")",
        "maxx": "$(json_escape "$GRIDSET_MAX_X")",
        "maxy": "$(json_escape "$GRIDSET_MAX_Y")"
    },
    "zoom_levels": ${GRIDSET_ZOOM_LEVELS},
    "layer_configured": ${LAYER_CONFIGURED},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_custom_gridset_result.json"

echo "=== Export complete ==="