#!/bin/bash
echo "=== Exporting style_rendering_order_sortby result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read initial state
INITIAL_COUNT=$(cat /tmp/initial_style_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_style_count)

EXPECTED_WS="ne"
EXPECTED_STYLE="cities_sorted"
LAYER_NAME="ne_populated_places"

STYLE_FOUND="false"
STYLE_BODY=""
STYLE_FORMAT=""
HAS_VENDOR_OPTION="false"
SORT_ATTRIBUTE=""
SORT_ORDER="asc" # Default if not specified
HAS_POINT_SYMBOLIZER="false"
IS_RED="false"
IS_CIRCLE="false"
LAYER_ASSOCIATED="false"

# 1. Check if style exists in workspace 'ne'
# We check specific workspace endpoint first
STATUS=$(gs_rest_status "workspaces/${EXPECTED_WS}/styles/${EXPECTED_STYLE}.json")
if [ "$STATUS" = "200" ]; then
    STYLE_FOUND="true"
    
    # Get the Style content (SLD)
    # GeoServer REST allows retrieving the SLD body directly
    STYLE_BODY=$(gs_rest_get_xml "workspaces/${EXPECTED_WS}/styles/${EXPECTED_STYLE}.sld")
    
    # Analyze SLD content using Python
    # We use a python script to parse the XML string safely
    ANALYSIS=$(echo "$STYLE_BODY" | python3 -c "
import sys, re
import xml.etree.ElementTree as ET

try:
    sld_content = sys.stdin.read()
    
    # Simple regex checks for robustness against namespace issues in XML parsing
    has_vendor = 'VendorOption' in sld_content and 'sortBy' in sld_content
    
    # Extract sortBy value
    sort_attr = ''
    sort_order = 'asc'
    
    # Regex to find <VendorOption name=\"sortBy\">content</VendorOption>
    # content matches: 'attribute' or 'attribute A' or 'attribute D'
    vo_match = re.search(r'<VendorOption\s+name=[\"\']sortBy[\"\']\s*>([^<]+)</VendorOption>', sld_content)
    if vo_match:
        content = vo_match.group(1).strip()
        parts = content.split()
        sort_attr = parts[0]
        if len(parts) > 1:
            if parts[1].upper().startswith('D'):
                sort_order = 'desc'
            else:
                sort_order = 'asc'
        else:
            sort_order = 'asc' # Default
            
    # Check Symbolizer
    has_point = 'PointSymbolizer' in sld_content
    
    # Check Color (Red #FF0000)
    # Could be in CssParameter or standard parameter
    is_red = '#FF0000' in sld_content.upper() or 'RED' in sld_content.upper()
    
    # Check Mark (Circle)
    is_circle = 'Circle' in sld_content or 'circle' in sld_content
    
    print(f'{has_vendor}|{sort_attr}|{sort_order}|{has_point}|{is_red}|{is_circle}')
    
except Exception as e:
    print('false||asc|false|false|false')
" 2>/dev/null)

    HAS_VENDOR_OPTION=$(echo "$ANALYSIS" | cut -d'|' -f1)
    SORT_ATTRIBUTE=$(echo "$ANALYSIS" | cut -d'|' -f2)
    SORT_ORDER=$(echo "$ANALYSIS" | cut -d'|' -f3)
    HAS_POINT_SYMBOLIZER=$(echo "$ANALYSIS" | cut -d'|' -f4)
    IS_RED=$(echo "$ANALYSIS" | cut -d'|' -f5)
    IS_CIRCLE=$(echo "$ANALYSIS" | cut -d'|' -f6)
fi

# 2. Check if style is associated with the layer
if [ "$STYLE_FOUND" = "true" ]; then
    LAYER_JSON=$(gs_rest_get "layers/${EXPECTED_WS}:${LAYER_NAME}.json")
    
    # Check if style is default or in styles list
    LAYER_ASSOCIATED=$(echo "$LAYER_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    layer = d.get('layer', {})
    
    # Check default style
    default_style = layer.get('defaultStyle', {}).get('name', '')
    if default_style == '${EXPECTED_STYLE}' or default_style == '${EXPECTED_WS}:${EXPECTED_STYLE}':
        print('true')
        sys.exit(0)
        
    # Check alternate styles
    styles = layer.get('styles', {}).get('style', [])
    if not isinstance(styles, list):
        styles = [styles]
        
    for s in styles:
        s_name = s.get('name', '')
        if s_name == '${EXPECTED_STYLE}' or s_name == '${EXPECTED_WS}:${EXPECTED_STYLE}':
            print('true')
            sys.exit(0)
            
    print('false')
except:
    print('false')
" 2>/dev/null)
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "style_found": ${STYLE_FOUND},
    "style_name": "${EXPECTED_STYLE}",
    "has_vendor_option": ${HAS_VENDOR_OPTION},
    "sort_attribute": "$(json_escape "$SORT_ATTRIBUTE")",
    "sort_order": "${SORT_ORDER}",
    "has_point_symbolizer": ${HAS_POINT_SYMBOLIZER},
    "is_red": ${IS_RED},
    "is_circle": ${IS_CIRCLE},
    "layer_associated": ${LAYER_ASSOCIATED},
    "initial_style_count": ${INITIAL_COUNT},
    "current_style_count": ${CURRENT_COUNT},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/style_rendering_order_sortby_result.json"

echo "=== Export complete ==="