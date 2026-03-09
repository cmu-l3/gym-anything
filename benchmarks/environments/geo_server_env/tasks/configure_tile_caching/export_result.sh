#!/bin/bash
echo "=== Exporting configure_tile_caching result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# 1. VERIFY GRIDSET CONFIGURATION (REST API)
# ==============================================================================
GRIDSET_NAME="WebMercator512"
GRIDSET_URL="${GWC_REST}/gridsets/${GRIDSET_NAME}.xml"

echo "Checking gridset at $GRIDSET_URL..."
HTTP_CODE=$(curl -s -o /tmp/gridset.xml -w "%{http_code}" -u "$GS_AUTH" "$GRIDSET_URL" 2>/dev/null)

GRIDSET_EXISTS="false"
GRIDSET_SRS=""
TILE_WIDTH=0
TILE_HEIGHT=0
ZOOM_LEVELS=0

if [ "$HTTP_CODE" = "200" ]; then
    GRIDSET_EXISTS="true"
    # Parse XML values (simple grep/sed as these are standard GWC XMLs)
    GRIDSET_SRS=$(grep -oP "(?<=<srs><number>)[^<]+" /tmp/gridset.xml || echo "")
    if [ -z "$GRIDSET_SRS" ]; then
        # Check standard srs tag structure
        GRIDSET_SRS=$(grep -oP "(?<=<srs>)[^<]+" /tmp/gridset.xml || echo "")
    fi
    
    TILE_WIDTH=$(grep -oP "(?<=<width>)[0-9]+" /tmp/gridset.xml | head -1 || echo "0")
    TILE_HEIGHT=$(grep -oP "(?<=<height>)[0-9]+" /tmp/gridset.xml | head -1 || echo "0")
    
    # Count scale denominators to determine zoom levels
    ZOOM_LEVELS=$(grep -c "<scaleDenominator>" /tmp/gridset.xml || echo "0")
fi

echo "Gridset Found: $GRIDSET_EXISTS"
echo "SRS: $GRIDSET_SRS"
echo "Size: ${TILE_WIDTH}x${TILE_HEIGHT}"
echo "Levels: $ZOOM_LEVELS"

# ==============================================================================
# 2. VERIFY LAYER CONFIGURATION (REST API)
# ==============================================================================
LAYER_NAME="ne:ne_countries"
LAYER_URL="${GWC_REST}/layers/${LAYER_NAME}.xml"

echo "Checking layer at $LAYER_URL..."
curl -s -u "$GS_AUTH" -o /tmp/layer.xml "$LAYER_URL" 2>/dev/null

LAYER_HAS_GRIDSET="false"
LAYER_HAS_PNG="false"

if [ -f /tmp/layer.xml ]; then
    if grep -q "<gridSetName>${GRIDSET_NAME}</gridSetName>" /tmp/layer.xml; then
        LAYER_HAS_GRIDSET="true"
    fi
    
    if grep -q "<string>image/png</string>" /tmp/layer.xml; then
        LAYER_HAS_PNG="true"
    fi
fi

echo "Layer linked to gridset: $LAYER_HAS_GRIDSET"
echo "Layer supports PNG: $LAYER_HAS_PNG"

# ==============================================================================
# 3. VERIFY FUNCTIONALITY (WMTS GetCapabilities & GetTile)
# ==============================================================================
WMTS_BASE="http://localhost:8080/geoserver/gwc/service/wmts"

# Check capabilities
WMTS_CAPS_FOUND="false"
curl -s "${WMTS_BASE}?service=WMTS&request=GetCapabilities" > /tmp/wmts_caps.xml 2>/dev/null
if grep -q "${GRIDSET_NAME}" /tmp/wmts_caps.xml; then
    WMTS_CAPS_FOUND="true"
fi

# Check GetTile (Functional Test)
# Request tile at zoom level 0, col 0, row 0
TILE_URL="${WMTS_BASE}?service=WMTS&request=GetTile&version=1.0.0&layer=${LAYER_NAME}&style=&tilematrixset=${GRIDSET_NAME}&tilematrix=${GRIDSET_NAME}:0&tilerow=0&tilecol=0&format=image/png"

echo "Testing Tile URL: $TILE_URL"
TILE_HTTP_CODE=$(curl -s -o /tmp/test_tile.png -w "%{http_code}" "$TILE_URL" 2>/dev/null)
TILE_SIZE_BYTES=$(stat -c%s /tmp/test_tile.png 2>/dev/null || echo "0")

# Check if it's actually an image
TILE_IS_IMAGE="false"
if file /tmp/test_tile.png | grep -q "PNG image data"; then
    TILE_IS_IMAGE="true"
fi

echo "Tile HTTP: $TILE_HTTP_CODE"
echo "Tile Size: $TILE_SIZE_BYTES"
echo "Tile Valid Image: $TILE_IS_IMAGE"

# ==============================================================================
# 4. ANTI-GAMING CHECKS
# ==============================================================================
# Check if gridset existed initially
PRE_EXISTING="false"
if [ -f /tmp/initial_gridsets.json ]; then
    if grep -q "${GRIDSET_NAME}" /tmp/initial_gridsets.json; then
        PRE_EXISTING="true"
    fi
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# ==============================================================================
# 5. EXPORT RESULT JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "gridset_exists": ${GRIDSET_EXISTS},
    "gridset_srs": "$(json_escape "$GRIDSET_SRS")",
    "tile_width": ${TILE_WIDTH},
    "tile_height": ${TILE_HEIGHT},
    "zoom_levels": ${ZOOM_LEVELS},
    "layer_has_gridset": ${LAYER_HAS_GRIDSET},
    "layer_has_png": ${LAYER_HAS_PNG},
    "wmts_caps_found": ${WMTS_CAPS_FOUND},
    "tile_http_code": ${TILE_HTTP_CODE},
    "tile_size_bytes": ${TILE_SIZE_BYTES},
    "tile_is_image": ${TILE_IS_IMAGE},
    "pre_existing_gridset": ${PRE_EXISTING},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_tile_caching_result.json"

echo "=== Export complete ==="
cat /tmp/configure_tile_caching_result.json