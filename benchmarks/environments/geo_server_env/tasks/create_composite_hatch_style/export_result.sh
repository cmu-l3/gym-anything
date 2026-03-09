#!/bin/bash
echo "=== Exporting create_composite_hatch_style result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# 1. Verify Style Existence & Content
# ============================================================
STYLE_EXISTS="false"
STYLE_WORKSPACE=""
STYLE_SLD=""

# Check in 'ne' workspace
HTTP_CODE=$(gs_rest_status "workspaces/ne/styles/composite_hatch.json")
if [ "$HTTP_CODE" = "200" ]; then
    STYLE_EXISTS="true"
    STYLE_WORKSPACE="ne"
    # Get the SLD content
    # Note: GeoServer REST API allows retrieving the SLD body directly via .sld extension
    STYLE_SLD=$(gs_rest_get_xml "workspaces/ne/styles/composite_hatch.sld")
fi

# ============================================================
# 2. Verify Layer Assignment
# ============================================================
LAYER_ASSIGNED="false"
CURRENT_DEFAULT_STYLE=""

LAYER_JSON=$(gs_rest_get "layers/ne:ne_countries.json")
if [ -n "$LAYER_JSON" ]; then
    # Extract default style name
    CURRENT_DEFAULT_STYLE=$(echo "$LAYER_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ds = d.get('layer', {}).get('defaultStyle', {})
    print(ds.get('name', ''))
except:
    print('')
" 2>/dev/null)

    # Check if it matches expected name (handling potential workspace prefix)
    if [ "$CURRENT_DEFAULT_STYLE" = "composite_hatch" ] || [ "$CURRENT_DEFAULT_STYLE" = "ne:composite_hatch" ]; then
        LAYER_ASSIGNED="true"
    fi
fi

# ============================================================
# 3. WMS Render Test (Functional Verification)
# ============================================================
# Request a map of the layer. If the style is broken, this often returns a service exception (XML) or blank image.
# We request a small image of Europe.
RENDER_SUCCESS="false"
RENDER_SIZE="0"
WMS_URL="${GS_URL}/ne/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image/png&TRANSPARENT=true&STYLES=&LAYERS=ne:ne_countries&SRS=EPSG:4326&WIDTH=300&HEIGHT=150&BBOX=-10,35,30,60"

curl -s -o /tmp/wms_test.png "$WMS_URL"
if [ -f /tmp/wms_test.png ]; then
    # Check if it's a PNG image (magic numbers) and size
    FILE_TYPE=$(file -b --mime-type /tmp/wms_test.png)
    FILE_SIZE=$(stat -c %s /tmp/wms_test.png)
    
    if [[ "$FILE_TYPE" == "image/png" ]] && [ "$FILE_SIZE" -gt 1000 ]; then
        RENDER_SUCCESS="true"
        RENDER_SIZE="$FILE_SIZE"
    else
        # Likely an XML error response
        echo "WMS Render failed. File type: $FILE_TYPE"
        cat /tmp/wms_test.png | head -n 5
    fi
fi

# ============================================================
# 4. JSON Export
# ============================================================
# Escape SLD content for JSON inclusion
ESCAPED_SLD=$(json_escape "$STYLE_SLD")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "style_exists": $STYLE_EXISTS,
    "style_workspace": "$STYLE_WORKSPACE",
    "layer_assigned": $LAYER_ASSIGNED,
    "assigned_style_name": "$CURRENT_DEFAULT_STYLE",
    "render_success": $RENDER_SUCCESS,
    "render_size": $RENDER_SIZE,
    "sld_content": "$ESCAPED_SLD",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "=== Export complete ==="