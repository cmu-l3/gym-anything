#!/bin/bash
echo "=== Exporting restrict_layer_crs_list result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get current FeatureType configuration via REST API
echo "Fetching final layer configuration..."
LAYER_CONFIG=$(gs_rest_get "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries.json")

# Extract the responseSRS list
SRS_LIST_JSON=$(echo "$LAYER_CONFIG" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    srs_list = d.get('featureType', {}).get('responseSRS', {}).get('string', [])
    if not isinstance(srs_list, list):
        srs_list = [srs_list] if srs_list else []
    print(json.dumps(srs_list))
except Exception:
    print('[]')
" 2>/dev/null)

# 2. Get WMS GetCapabilities to verify what is actually advertised
echo "Fetching WMS GetCapabilities..."
CAPABILITIES_XML=$(curl -s "${GS_URL}/ne/wms?service=WMS&version=1.3.0&request=GetCapabilities")

# Parse Capabilities to find the ne_countries layer and its CRS list
# We use python for robust XML parsing
CAPABILITIES_ANALYSIS=$(echo "$CAPABILITIES_XML" | python3 -c "
import sys, json
import xml.etree.ElementTree as ET

try:
    # Read XML from stdin
    xml_content = sys.stdin.read()
    root = ET.fromstring(xml_content)
    
    # Namespace map for WMS 1.3.0
    ns = {'wms': 'http://www.opengis.net/wms'}
    
    # Find the specific layer
    # Note: Layers can be nested. We search recursively.
    target_layer_name = 'ne_countries'
    found_layer = None
    
    for layer in root.findall('.//wms:Layer', ns):
        name_elem = layer.find('wms:Name', ns)
        if name_elem is not None and name_elem.text == target_layer_name:
            found_layer = layer
            break
            
    result = {
        'found': False,
        'crs_list': [],
        'count': 0
    }
    
    if found_layer is not None:
        result['found'] = True
        # Extract CRS elements (WMS 1.3.0 uses CRS, 1.1.1 uses SRS)
        crs_elems = found_layer.findall('wms:CRS', ns)
        crs_values = [elem.text for elem in crs_elems if elem.text]
        result['crs_list'] = crs_values
        result['count'] = len(crs_values)
        
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({'error': str(e), 'found': False}))
" 2>/dev/null)


# 3. Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# 4. Generate integrity nonce
NONCE=$(generate_result_nonce)

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "rest_srs_list": $SRS_LIST_JSON,
    "capabilities_analysis": $CAPABILITIES_ANALYSIS,
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$NONCE",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/restrict_layer_crs_result.json"

echo "=== Export complete ==="