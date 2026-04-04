#!/bin/bash
echo "=== Exporting configure_label_priority result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

take_screenshot /tmp/task_end_screenshot.png

# Read initial state
INITIAL_STYLE_COUNT=$(cat /tmp/initial_style_count 2>/dev/null || echo "0")
CURRENT_STYLE_COUNT=$(get_style_count)

# ==============================================================================
# 1. Check if the style exists
# ==============================================================================
EXPECTED_STYLE="city_labels_priority"
STYLE_FOUND="false"
STYLE_DATA=""
SLD_CONTENT=""

# Check exact name
if [ "$(gs_rest_status "styles/${EXPECTED_STYLE}.json")" = "200" ]; then
    STYLE_FOUND="true"
    # Get SLD body (SLD 1.0.0 or 1.1.0)
    SLD_CONTENT=$(gs_rest_get_xml "styles/${EXPECTED_STYLE}.sld")
fi

# ==============================================================================
# 2. Check Layer Assignment
# ==============================================================================
LAYER_ASSIGNED="false"
LAYER_DEFAULT_STYLE=""

# Get ne_populated_places layer config
LAYER_JSON=$(gs_rest_get "layers/ne:ne_populated_places.json")
if [ -n "$LAYER_JSON" ]; then
    LAYER_DEFAULT_STYLE=$(echo "$LAYER_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('layer', {}).get('defaultStyle', {}).get('name', ''))
except:
    print('')
" 2>/dev/null)
fi

if [ "$LAYER_DEFAULT_STYLE" = "$EXPECTED_STYLE" ]; then
    LAYER_ASSIGNED="true"
fi

# ==============================================================================
# 3. Parse SLD Content
# ==============================================================================
# We use Python to parse the XML safely and extract specific styling rules
PARSED_SLD=$(python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    sld_content = sys.stdin.read()
    if not sld_content.strip():
        print('{}')
        sys.exit(0)
        
    root = ET.fromstring(sld_content)
    
    # Helper to strip namespaces
    def tag(elem):
        return elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag

    result = {
        'has_text_symbolizer': False,
        'has_point_symbolizer': False,
        'priority_attr': None,
        'space_around': None,
        'font_family': None,
        'font_weight': None,
        'font_size': None,
        'label_attr': None
    }

    # Iterate through all elements
    for elem in root.iter():
        t = tag(elem)
        
        if t == 'PointSymbolizer':
            result['has_point_symbolizer'] = True
            
        if t == 'TextSymbolizer':
            result['has_text_symbolizer'] = True
            
            # Check Priority
            for child in elem:
                if tag(child) == 'Priority':
                    # Look for PropertyName inside Priority
                    for p in child.iter():
                        if tag(p) == 'PropertyName':
                            result['priority_attr'] = (p.text or '').strip()
            
            # Check Label
            for child in elem:
                if tag(child) == 'Label':
                     for p in child.iter():
                        if tag(p) == 'PropertyName':
                            result['label_attr'] = (p.text or '').strip()

            # Check Font
            for child in elem:
                if tag(child) == 'Font':
                    for css in child:
                        if tag(css) == 'CssParameter':
                            name = css.get('name')
                            val = (css.text or '').strip()
                            if name == 'font-family': result['font_family'] = val
                            if name == 'font-weight': result['font_weight'] = val
                            if name == 'font-size': result['font_size'] = val

            # Check VendorOption
            for child in elem:
                if tag(child) == 'VendorOption':
                    if child.get('name') == 'spaceAround':
                        result['space_around'] = (child.text or '').strip()

    import json
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" <<< "$SLD_CONTENT" 2>/dev/null)

# ==============================================================================
# 4. Check GUI Interaction
# ==============================================================================
GUI_INTERACTION=$(check_gui_interaction)

# ==============================================================================
# 5. Create JSON Result
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "style_found": $STYLE_FOUND,
    "style_name": "$EXPECTED_STYLE",
    "layer_assigned": $LAYER_ASSIGNED,
    "assigned_style": "$(json_escape "$LAYER_DEFAULT_STYLE")",
    "sld_analysis": $PARSED_SLD,
    "initial_style_count": $INITIAL_STYLE_COUNT,
    "current_style_count": $CURRENT_STYLE_COUNT,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_label_priority_result.json"

echo "=== Export complete ==="