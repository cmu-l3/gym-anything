#!/bin/bash
echo "=== Exporting register_custom_crs_layer result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Check user_projections/epsg.properties for the custom CRS
# We need to read this from the Docker container
echo "Checking epsg.properties..."
EPSG_PROPS=$(docker exec gs-app cat /opt/geoserver/data_dir/user_projections/epsg.properties 2>/dev/null || echo "")

CRS_REGISTERED="false"
WKT_CORRECT="false"
CRS_CODE="990001"

if echo "$EPSG_PROPS" | grep -q "^990001="; then
    CRS_REGISTERED="true"
    # Check for critical parameter (central_meridian 150.0) in the WKT definition
    # We use a loose grep to handle potential whitespace variations
    if echo "$EPSG_PROPS" | grep "^990001=" | grep -q "central_meridian.*150\.0"; then
        WKT_CORRECT="true"
    fi
fi

# 2. Check for the new layer
LAYER_NAME="ne_countries_pacific"
LAYER_FOUND="false"
LAYER_SRS=""
PROJECTION_POLICY=""
LAYER_ENABLED="false"

# Check REST API
LAYER_JSON=$(gs_rest_get "layers/${LAYER_NAME}.json")
if echo "$LAYER_JSON" | grep -q "\"name\":\"${LAYER_NAME}\""; then
    LAYER_FOUND="true"
    LAYER_ENABLED=$(echo "$LAYER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('layer',{}).get('enabled', False)).lower())" 2>/dev/null || echo "false")
    
    # Get feature type details for SRS and policy
    RESOURCE_HREF=$(echo "$LAYER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('resource',{}).get('href',''))" 2>/dev/null)
    
    if [ -n "$RESOURCE_HREF" ]; then
        FT_JSON=$(curl -s -u "$GS_AUTH" -H "Accept: application/json" "$RESOURCE_HREF")
        LAYER_SRS=$(echo "$FT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('featureType',{}).get('srs',''))" 2>/dev/null)
        PROJECTION_POLICY=$(echo "$FT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('featureType',{}).get('projectionPolicy',''))" 2>/dev/null)
    fi
fi

# 3. Functional Test: WMS GetMap with the custom SRS
# We attempt to fetch a map of the Pacific using EPSG:990001
WMS_SUCCESS="false"
WMS_IMAGE_SIZE="0"

if [ "$LAYER_FOUND" = "true" ]; then
    WMS_URL="${GS_URL}/ne/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&FORMAT=image/png&TRANSPARENT=true&STYLES&LAYERS=ne:${LAYER_NAME}&SRS=EPSG:${CRS_CODE}&WIDTH=768&HEIGHT=384&BBOX=-20000000,-10000000,20000000,10000000"
    
    # Download the image
    curl -s -u "$GS_AUTH" -o /tmp/wms_test.png "$WMS_URL"
    
    if [ -f /tmp/wms_test.png ]; then
        # Check if it's a valid PNG and not an XML exception
        if file /tmp/wms_test.png | grep -q "PNG image data"; then
            WMS_SUCCESS="true"
            WMS_IMAGE_SIZE=$(stat -c %s /tmp/wms_test.png)
        else
            # Save exception for debugging
            cat /tmp/wms_test.png > /tmp/wms_error.xml
        fi
    fi
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "crs_registered": ${CRS_REGISTERED},
    "wkt_correct": ${WKT_CORRECT},
    "layer_found": ${LAYER_FOUND},
    "layer_name": "$(json_escape "$LAYER_NAME")",
    "layer_srs": "$(json_escape "$LAYER_SRS")",
    "projection_policy": "$(json_escape "$PROJECTION_POLICY")",
    "wms_success": ${WMS_SUCCESS},
    "wms_image_size": ${WMS_IMAGE_SIZE},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/register_custom_crs_result.json"

echo "=== Export complete ==="