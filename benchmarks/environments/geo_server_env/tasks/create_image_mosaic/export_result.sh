#!/bin/bash
echo "=== Exporting create_image_mosaic result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Task Constants
WS_NAME="imagery"
STORE_NAME="world_mosaic_store"
LAYER_NAME="global_mask"

# 1. Check Workspace
WS_FOUND="false"
WS_STATUS=$(gs_rest_status "workspaces/${WS_NAME}.json")
if [ "$WS_STATUS" = "200" ]; then
    WS_FOUND="true"
fi

# 2. Check Store
STORE_FOUND="false"
STORE_TYPE=""
STORE_URL=""
STORE_STATUS=$(gs_rest_status "workspaces/${WS_NAME}/coveragestores/${STORE_NAME}.json")
if [ "$STORE_STATUS" = "200" ]; then
    STORE_DATA=$(gs_rest_get "workspaces/${WS_NAME}/coveragestores/${STORE_NAME}.json")
    STORE_FOUND="true"
    STORE_TYPE=$(echo "$STORE_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin).get('coverageStore',{}).get('type',''))" 2>/dev/null || echo "")
    STORE_URL=$(echo "$STORE_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin).get('coverageStore',{}).get('url',''))" 2>/dev/null || echo "")
fi

# 3. Check Layer (Coverage)
LAYER_FOUND="false"
LAYER_ENABLED="false"
LAYER_SRS=""
LAYER_BBOX=""
LAYER_STATUS=$(gs_rest_status "workspaces/${WS_NAME}/coveragestores/${STORE_NAME}/coverages/${LAYER_NAME}.json")
if [ "$LAYER_STATUS" = "200" ]; then
    LAYER_DATA=$(gs_rest_get "workspaces/${WS_NAME}/coveragestores/${STORE_NAME}/coverages/${LAYER_NAME}.json")
    LAYER_FOUND="true"
    LAYER_ENABLED=$(echo "$LAYER_DATA" | python3 -c "import sys,json; print(str(json.load(sys.stdin).get('coverage',{}).get('enabled',False)).lower())" 2>/dev/null || echo "false")
    LAYER_SRS=$(echo "$LAYER_DATA" | python3 -c "import sys,json; print(json.load(sys.stdin).get('coverage',{}).get('srs',''))" 2>/dev/null || echo "")
    # Check bbox
    LAYER_BBOX=$(echo "$LAYER_DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin)
nb = d.get('coverage', {}).get('latLonBoundingBox', {})
print(f\"{nb.get('minx','')},{nb.get('miny','')},{nb.get('maxx','')},{nb.get('maxy','')}\")
" 2>/dev/null || echo "")
fi

# 4. Visual Verification (WMS GetMap)
# Only attempt if layer exists
VALID_IMAGE="false"
IMAGE_STD_DEV="0"

if [ "$LAYER_FOUND" = "true" ] && [ "$LAYER_ENABLED" = "true" ]; then
    echo "Verifying WMS output..."
    # Request a map covering the intersection of 4 tiles (0,0)
    # Use a style that doesn't mask data (default raster style usually works)
    WMS_URL="${GS_URL}/${WS_NAME}/wms?service=WMS&version=1.1.0&request=GetMap&layers=${WS_NAME}:${LAYER_NAME}&styles=&bbox=-10,-10,10,10&width=256&height=256&srs=EPSG:4326&format=image/png"
    
    curl -s "$WMS_URL" -o /tmp/mosaic_check.png
    
    if [ -f /tmp/mosaic_check.png ]; then
        FILE_TYPE=$(file --mime-type -b /tmp/mosaic_check.png)
        FILE_SIZE=$(stat -c%s /tmp/mosaic_check.png)
        
        if [ "$FILE_TYPE" = "image/png" ] && [ "$FILE_SIZE" -gt 100 ]; then
            VALID_IMAGE="true"
            # Calculate standard deviation to check for content (contrast between land/water)
            # 0 = solid color (blank), >0 = content
            IMAGE_STD_DEV=$(convert /tmp/mosaic_check.png -format "%[fx:standard_deviation]" info: 2>/dev/null || echo "0")
        else
            echo "WMS request failed or returned invalid image (Type: $FILE_TYPE, Size: $FILE_SIZE)"
            # If it's XML, cat it for debugging log
            if [ "$FILE_TYPE" != "image/png" ]; then
                cat /tmp/mosaic_check.png
            fi
        fi
    fi
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "workspace_found": ${WS_FOUND},
    "store_found": ${STORE_FOUND},
    "store_type": "$(json_escape "$STORE_TYPE")",
    "store_url": "$(json_escape "$STORE_URL")",
    "layer_found": ${LAYER_FOUND},
    "layer_enabled": ${LAYER_ENABLED},
    "layer_srs": "$(json_escape "$LAYER_SRS")",
    "layer_bbox": "$(json_escape "$LAYER_BBOX")",
    "wms_image_valid": ${VALID_IMAGE},
    "wms_image_std_dev": "${IMAGE_STD_DEV}",
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_image_mosaic_result.json"

echo "=== Export complete ==="