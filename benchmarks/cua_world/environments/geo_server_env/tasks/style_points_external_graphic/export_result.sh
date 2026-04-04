#!/bin/bash
echo "=== Exporting style_points_external_graphic result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# Check 1: SVG File Existence and Content
# ============================================================
SVG_FOUND="false"
SVG_PATH=""
SVG_CONTENT=""
SVG_TIMESTAMP="0"

# Search for star.svg in the container's data directory
# Common locations: data_dir/styles/star.svg or data_dir/workspaces/ne/styles/star.svg
SVG_LOCATIONS=$(docker exec gs-app bash -c "find /opt/geoserver/data_dir -name 'star.svg' 2>/dev/null")

if [ -n "$SVG_LOCATIONS" ]; then
    SVG_FOUND="true"
    # Take the first one found
    SVG_PATH=$(echo "$SVG_LOCATIONS" | head -n 1)
    # Read content (first 1000 chars to avoid huge dump)
    SVG_CONTENT=$(docker exec gs-app cat "$SVG_PATH" | head -c 1000)
    # Get timestamp
    SVG_TIMESTAMP=$(docker exec gs-app stat -c %Y "$SVG_PATH")
    echo "Found SVG at $SVG_PATH"
else
    echo "star.svg NOT found in container"
fi

# ============================================================
# Check 2: Style Definition (REST API)
# ============================================================
STYLE_FOUND="false"
STYLE_NAME=""
STYLE_SLD=""

# Check global style
STATUS=$(gs_rest_status "styles/star_marker.json")
if [ "$STATUS" == "200" ]; then
    STYLE_FOUND="true"
    STYLE_NAME="star_marker"
    STYLE_SLD=$(gs_rest_get_xml "styles/star_marker.sld")
else
    # Check workspace style
    STATUS_WS=$(gs_rest_status "workspaces/ne/styles/star_marker.json")
    if [ "$STATUS_WS" == "200" ]; then
        STYLE_FOUND="true"
        STYLE_NAME="ne:star_marker"
        STYLE_SLD=$(gs_rest_get_xml "workspaces/ne/styles/star_marker.sld")
    fi
fi

# ============================================================
# Check 3: Layer Assignment (REST API)
# ============================================================
LAYER_STYLE_CORRECT="false"
LAYER_DEFAULT_STYLE=""

LAYER_JSON=$(gs_rest_get "layers/ne:ne_populated_places.json")
LAYER_DEFAULT_STYLE=$(echo "$LAYER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null)

if [ "$LAYER_DEFAULT_STYLE" == "star_marker" ] || [ "$LAYER_DEFAULT_STYLE" == "ne:star_marker" ]; then
    LAYER_STYLE_CORRECT="true"
fi

# ============================================================
# Check 4: WMS Rendering (Functional Test)
# ============================================================
WMS_WORKS="false"
WMS_SIZE_BYTES="0"

# Request map of populated places
# We use a bbox that definitely contains points (New York area)
curl -s -o /tmp/wms_test.png "http://localhost:8080/geoserver/ne/wms?service=WMS&version=1.1.0&request=GetMap&layers=ne:ne_populated_places&styles=&bbox=-75,40,-73,42&width=200&height=200&srs=EPSG:4326&format=image/png"
WMS_HTTP_CODE=$?

if [ -f /tmp/wms_test.png ]; then
    WMS_SIZE_BYTES=$(stat -c %s /tmp/wms_test.png)
    # Check if it's a valid PNG and not an XML error
    if file /tmp/wms_test.png | grep -q "PNG image data"; then
        WMS_WORKS="true"
    fi
fi

# ============================================================
# GUI Interaction Check
# ============================================================
GUI_INTERACTION=$(check_gui_interaction)

# ============================================================
# Export JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "svg_found": $SVG_FOUND,
    "svg_path": "$(json_escape "$SVG_PATH")",
    "svg_content": "$(json_escape "$SVG_CONTENT")",
    "svg_timestamp": $SVG_TIMESTAMP,
    "style_found": $STYLE_FOUND,
    "style_name": "$(json_escape "$STYLE_NAME")",
    "style_sld": "$(json_escape "$STYLE_SLD")",
    "layer_default_style": "$(json_escape "$LAYER_DEFAULT_STYLE")",
    "layer_style_correct": $LAYER_STYLE_CORRECT,
    "wms_works": $WMS_WORKS,
    "wms_size_bytes": $WMS_SIZE_BYTES,
    "gui_interaction_detected": $GUI_INTERACTION,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/style_points_result.json"
echo "=== Export complete ==="