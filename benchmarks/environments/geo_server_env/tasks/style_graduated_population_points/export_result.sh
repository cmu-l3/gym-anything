#!/bin/bash
echo "=== Exporting style_graduated_population_points result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read initial state
INITIAL_COUNT=$(cat /tmp/initial_style_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_style_count)

EXPECTED_WS="ne"
EXPECTED_STYLE="graduated_pop"
EXPECTED_LAYER="ne_populated_places"

STYLE_FOUND="false"
STYLE_CONTENT=""
LAYER_ASSOCIATED="false"
IS_DEFAULT_STYLE="false"

# 1. Check if style exists in workspace 'ne'
# GeoServer REST API for styles in workspace: /workspaces/{workspace}/styles/{style}
HTTP_CODE=$(gs_rest_status "workspaces/${EXPECTED_WS}/styles/${EXPECTED_STYLE}.json")

if [ "$HTTP_CODE" = "200" ]; then
    STYLE_FOUND="true"
    # Fetch the SLD content
    STYLE_CONTENT=$(gs_rest_get_xml "workspaces/${EXPECTED_WS}/styles/${EXPECTED_STYLE}.sld")
else
    # Fallback: check global styles
    HTTP_CODE=$(gs_rest_status "styles/${EXPECTED_STYLE}.json")
    if [ "$HTTP_CODE" = "200" ]; then
        STYLE_FOUND="true"
        STYLE_CONTENT=$(gs_rest_get_xml "styles/${EXPECTED_STYLE}.sld")
    fi
fi

# 2. Check association with layer
# Get layer definition: /workspaces/{workspace}/layers/{layer}.json
LAYER_JSON=$(gs_rest_get "workspaces/${EXPECTED_WS}/layers/${EXPECTED_LAYER}.json")

# Check default style
DEFAULT_STYLE=$(echo "$LAYER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null)

# Check alternate styles (styles is a list of dicts)
ALTERNATE_STYLES=$(echo "$LAYER_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
styles = d.get('layer', {}).get('styles', {}).get('style', [])
if isinstance(styles, dict): styles = [styles]
names = [s.get('name') for s in styles if 'name' in s]
print(','.join(names))
" 2>/dev/null)

# Verify if our style is linked
if [ "$DEFAULT_STYLE" == "$EXPECTED_STYLE" ] || [ "$DEFAULT_STYLE" == "${EXPECTED_WS}:${EXPECTED_STYLE}" ]; then
    LAYER_ASSOCIATED="true"
    IS_DEFAULT_STYLE="true"
elif [[ ",$ALTERNATE_STYLES," == *",$EXPECTED_STYLE,"* ]] || [[ ",$ALTERNATE_STYLES," == *","${EXPECTED_WS}:${EXPECTED_STYLE}","* ]]; then
    LAYER_ASSOCIATED="true"
fi

# 3. GUI Interaction Check
GUI_INTERACTION=$(check_gui_interaction)

# 4. Generate a WMS GetMap request to verify it renders (if style found)
RENDER_SUCCESS="false"
if [ "$STYLE_FOUND" = "true" ]; then
    # Try to render a small image using the style
    # BBOX for world: -180,-90,180,90
    TEST_IMG="/tmp/style_test_render.png"
    HTTP_RENDER=$(curl -s -o "$TEST_IMG" -w "%{http_code}" \
        "http://localhost:8080/geoserver/${EXPECTED_WS}/wms?service=WMS&version=1.1.0&request=GetMap&layers=${EXPECTED_WS}:${EXPECTED_LAYER}&styles=${EXPECTED_WS}:${EXPECTED_STYLE}&bbox=-180,-90,180,90&width=100&height=50&srs=EPSG:4326&format=image/png" \
        2>/dev/null)
    
    if [ "$HTTP_RENDER" = "200" ] && [ -s "$TEST_IMG" ]; then
        # Check if image is valid PNG and not an XML error
        if file "$TEST_IMG" | grep -q "PNG image data"; then
            RENDER_SUCCESS="true"
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# Escape SLD content for JSON
ESCAPED_SLD=$(json_escape "$STYLE_CONTENT")

cat > "$TEMP_JSON" << EOF
{
    "style_found": $STYLE_FOUND,
    "style_name": "$EXPECTED_STYLE",
    "sld_content": "$ESCAPED_SLD",
    "layer_associated": $LAYER_ASSOCIATED,
    "is_default_style": $IS_DEFAULT_STYLE,
    "render_success": $RENDER_SUCCESS,
    "initial_style_count": $INITIAL_COUNT,
    "current_style_count": $CURRENT_COUNT,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/style_graduated_population_points_result.json"

echo "=== Export complete ==="