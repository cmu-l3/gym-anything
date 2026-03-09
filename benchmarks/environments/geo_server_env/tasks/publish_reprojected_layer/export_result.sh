#!/bin/bash
set -e
echo "=== Exporting task result: publish_reprojected_layer ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_final_state.png

# Initialize result variables
SCORE=0
DETAILS=""
LAYER_EXISTS="false"
NATIVE_NAME=""
DECLARED_SRS=""
PROJ_POLICY=""
LAYER_TITLE=""
WMS_SUCCESS="false"
WMS_CONTENT="false"
IMAGE_SIZE_BYTES=0
COLORS=0

# ============================================================
# Check 1: Feature type ne_countries_3857 exists
# ============================================================
FT_RESPONSE=$(gs_rest_get "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries_3857.json" 2>/dev/null)
FT_STATUS=$(gs_rest_status "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries_3857")

if [ "$FT_STATUS" = "200" ] && [ -n "$FT_RESPONSE" ]; then
    LAYER_EXISTS="true"
    
    # Parse the feature type response
    NATIVE_NAME=$(echo "$FT_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('featureType', {}).get('nativeName', ''))" 2>/dev/null)
    DECLARED_SRS=$(echo "$FT_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('featureType', {}).get('srs', ''))" 2>/dev/null)
    PROJ_POLICY=$(echo "$FT_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('featureType', {}).get('projectionPolicy', ''))" 2>/dev/null)
    LAYER_TITLE=$(echo "$FT_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('featureType', {}).get('title', ''))" 2>/dev/null)
fi

# ============================================================
# Check 2: WMS GetMap Functional Test (EPSG:3857)
# ============================================================
GETMAP_URL="${GS_URL}/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&LAYERS=ne:ne_countries_3857&STYLES=&SRS=EPSG:3857&BBOX=-20037508.34,-20037508.34,20037508.34,20037508.34&WIDTH=512&HEIGHT=512&FORMAT=image/png"

HTTP_CODE=$(curl -s -o /tmp/getmap_3857.png -w "%{http_code}" "$GETMAP_URL" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ] && [ -f /tmp/getmap_3857.png ]; then
    FILE_TYPE=$(file -b /tmp/getmap_3857.png 2>/dev/null || echo "unknown")
    if echo "$FILE_TYPE" | grep -qi "PNG\|image"; then
        WMS_SUCCESS="true"
        IMAGE_SIZE_BYTES=$(stat -c%s /tmp/getmap_3857.png 2>/dev/null || echo "0")
        
        # Check image content (standard deviation/colors)
        COLORS=$(identify -verbose /tmp/getmap_3857.png 2>/dev/null | grep "Number of colors" | awk '{print $NF}' || echo "0")
        if [ "$COLORS" -gt 5 ] 2>/dev/null; then
            WMS_CONTENT="true"
        fi
        
        # Fallback if identify fails or returns 0 (some versions)
        if [ "$WMS_CONTENT" = "false" ] && [ "$IMAGE_SIZE_BYTES" -gt 3000 ]; then
             WMS_CONTENT="true"
        fi
    fi
fi

# ============================================================
# Anti-gaming: Layer Counts
# ============================================================
INITIAL_LAYER_COUNT=$(cat /tmp/initial_layer_count.txt 2>/dev/null || echo "0")
CURRENT_LAYER_COUNT=$(get_layer_count)

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction 2>/dev/null || echo "unknown")

# ============================================================
# Create JSON Result
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "layer_exists": ${LAYER_EXISTS},
    "native_name": "$(json_escape "$NATIVE_NAME")",
    "declared_srs": "$(json_escape "$DECLARED_SRS")",
    "projection_policy": "$(json_escape "$PROJ_POLICY")",
    "layer_title": "$(json_escape "$LAYER_TITLE")",
    "wms_success": ${WMS_SUCCESS},
    "wms_content_valid": ${WMS_CONTENT},
    "image_size_bytes": ${IMAGE_SIZE_BYTES},
    "image_colors": ${COLORS:-0},
    "initial_layer_count": ${INITIAL_LAYER_COUNT},
    "current_layer_count": ${CURRENT_LAYER_COUNT},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "=== Export complete ==="
cat /tmp/task_result.json