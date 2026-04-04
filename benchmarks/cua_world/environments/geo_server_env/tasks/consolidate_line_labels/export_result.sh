#!/bin/bash
echo "=== Exporting consolidate_line_labels result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if the style exists and retrieve its content
STYLE_NAME="river_labels"
WORKSPACE="ne"
STYLE_EXISTS="false"
STYLE_CONTENT=""

# Try workspace-specific style first
HTTP_CODE=$(gs_rest_status "workspaces/${WORKSPACE}/styles/${STYLE_NAME}.sld")
if [ "$HTTP_CODE" = "200" ]; then
    STYLE_EXISTS="true"
    STYLE_CONTENT=$(gs_rest_get_xml "workspaces/${WORKSPACE}/styles/${STYLE_NAME}.sld")
else
    # Try global style
    HTTP_CODE=$(gs_rest_status "styles/${STYLE_NAME}.sld")
    if [ "$HTTP_CODE" = "200" ]; then
        STYLE_EXISTS="true"
        STYLE_CONTENT=$(gs_rest_get_xml "styles/${STYLE_NAME}.sld")
    fi
fi

# 2. Check if the layer uses this style
LAYER_NAME="ne_rivers"
LAYER_DEFAULT_STYLE=""
LAYER_USES_STYLE="false"

LAYER_JSON=$(gs_rest_get "layers/${WORKSPACE}:${LAYER_NAME}.json")
if [ -n "$LAYER_JSON" ]; then
    # Extract default style name safely using python
    LAYER_DEFAULT_STYLE=$(echo "$LAYER_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    style = d.get('layer', {}).get('defaultStyle', {})
    print(style.get('name', '') or style.get('id', ''))
except:
    print('')
")
    
    # Check match (handle workspace prefix if present)
    if [ "$LAYER_DEFAULT_STYLE" = "$STYLE_NAME" ] || [ "$LAYER_DEFAULT_STYLE" = "${WORKSPACE}:${STYLE_NAME}" ]; then
        LAYER_USES_STYLE="true"
    fi
fi

# 3. Check if WMS GetMap returns a valid image (not an exception)
# This confirms the SLD is syntactically valid and renderable
WMS_URL="${GS_URL}/ne/wms?service=WMS&version=1.1.0&request=GetMap&layers=${WORKSPACE}:${LAYER_NAME}&styles=${STYLE_NAME}&bbox=-180,-90,180,90&width=256&height=128&srs=EPSG:4326&format=image/png"
WMS_HTTP_CODE=$(curl -s -o /tmp/wms_test.png -w "%{http_code}" -u "$GS_AUTH" "$WMS_URL")
VALID_RENDER="false"
if [ "$WMS_HTTP_CODE" = "200" ]; then
    # Check if it's actually an image, not an XML error disguised as 200 (though GS usually sends 200 for exceptions with correct headers, file command tells truth)
    if file /tmp/wms_test.png | grep -q "PNG image data"; then
        VALID_RENDER="true"
    fi
fi

# 4. Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# 5. Create JSON result using Python to safely escape the SLD XML content
python3 -c "
import json
import os
import sys

try:
    result = {
        'style_exists': $STYLE_EXISTS,
        'style_name': '$STYLE_NAME',
        'style_content': '''$STYLE_CONTENT''',
        'layer_uses_style': $LAYER_USES_STYLE,
        'layer_default_style': '$LAYER_DEFAULT_STYLE',
        'valid_render': $VALID_RENDER,
        'gui_interaction_detected': $GUI_INTERACTION,
        'timestamp': '$(date -Iseconds)'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error creating result JSON: {e}', file=sys.stderr)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="