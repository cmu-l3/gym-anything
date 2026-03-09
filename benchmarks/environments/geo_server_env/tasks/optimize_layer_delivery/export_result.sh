#!/bin/bash
echo "=== Exporting optimize_layer_delivery result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# 1. Verify HTTP Cache Headers (Service Response)
# ==============================================================================
# Make a GetMap request and inspect headers
echo "Checking WMS GetMap headers..."
HEADERS_FILE=$(mktemp)
curl -s -I "http://localhost:8080/geoserver/ne/wms?service=WMS&version=1.1.1&request=GetMap&layers=ne:ne_countries&styles=&bbox=-180,-90,180,90&width=100&height=50&srs=EPSG:4326&format=image/png" > "$HEADERS_FILE"

CACHE_CONTROL=$(grep -i "Cache-Control" "$HEADERS_FILE" | tr -d '\r')
echo "Headers found: $CACHE_CONTROL"

# Extract max-age value if present
MAX_AGE="0"
if echo "$CACHE_CONTROL" | grep -q "max-age="; then
    MAX_AGE=$(echo "$CACHE_CONTROL" | grep -o "max-age=[0-9]*" | cut -d= -f2)
fi
echo "Detected max-age: $MAX_AGE"

rm -f "$HEADERS_FILE"

# ==============================================================================
# 2. Verify Attribution (GetCapabilities)
# ==============================================================================
echo "Checking WMS Capabilities..."
CAPS_FILE=$(mktemp)
curl -s "http://localhost:8080/geoserver/ne/wms?service=WMS&version=1.3.0&request=GetCapabilities" > "$CAPS_FILE"

# Use Python to parse the XML specifically for the ne:ne_countries layer attribution
# We look for <Layer> with <Name>ne:ne_countries</Name> and extract its <Attribution> children
ATTRIBUTION_JSON=$(python3 -c "
import sys
import xml.etree.ElementTree as ET
import json

try:
    tree = ET.parse('$CAPS_FILE')
    root = tree.getroot()
    # Namespace map for WMS 1.3.0
    ns = {'wms': 'http://www.opengis.net/wms'}
    
    result = {
        'found': False,
        'title': '',
        'logo_url': '',
        'logo_format': '',
        'logo_width': 0,
        'logo_height': 0
    }

    # Find the specific layer
    # Note: recursing through layers to find the one with Name = ne:ne_countries
    for layer in root.findall('.//wms:Layer', ns):
        name = layer.find('wms:Name', ns)
        if name is not None and name.text == 'ne:ne_countries':
            result['found'] = True
            attr = layer.find('wms:Attribution', ns)
            if attr is not None:
                title = attr.find('wms:Title', ns)
                if title is not None:
                    result['title'] = title.text
                
                logo = attr.find('wms:LogoURL', ns)
                if logo is not None:
                    result['logo_width'] = int(logo.get('width', 0))
                    result['logo_height'] = int(logo.get('height', 0))
                    
                    fmt = logo.find('wms:Format', ns)
                    if fmt is not None:
                        result['logo_format'] = fmt.text
                        
                    res = logo.find('wms:OnlineResource', ns)
                    if res is not None:
                        # xlink:href usually
                        result['logo_url'] = res.attrib.get('{http://www.w3.org/1999/xlink}href', '')
            break
            
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'error': str(e)}))
")

echo "Attribution parsed: $ATTRIBUTION_JSON"
rm -f "$CAPS_FILE"

# ==============================================================================
# 3. Verify via REST API (Configuration Check)
# ==============================================================================
# This is a backup to ensure settings are persisted even if WMS service is acting up
LAYER_CONFIG=$(gs_rest_get "layers/ne:ne_countries.json")
REST_ATTRIBUTION=$(echo "$LAYER_CONFIG" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('layer',{}).get('attribution',{})))" 2>/dev/null || echo "{}")

# ==============================================================================
# 4. Anti-Gaming & Export
# ==============================================================================
# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cache_control_header": "$(json_escape "$CACHE_CONTROL")",
    "cache_max_age": "$MAX_AGE",
    "attribution_xml": $ATTRIBUTION_JSON,
    "rest_attribution": $REST_ATTRIBUTION,
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/optimize_layer_delivery_result.json"

echo "=== Export complete ==="