#!/bin/bash
echo "=== Exporting create_style result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read initial state
INITIAL_COUNT=$(cat /tmp/initial_style_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_style_count)

# Check for the expected style via REST API
EXPECTED_NAME="blue_polygon"
STYLE_FOUND="false"
STYLE_NAME=""
STYLE_FORMAT=""
STYLE_HAS_FILL="false"
STYLE_HAS_STROKE="false"
STYLE_SLD_CONTENT=""

# Try exact match first
STYLE_STATUS=$(gs_rest_status "styles/${EXPECTED_NAME}.json")
if [ "$STYLE_STATUS" = "200" ]; then
    STYLE_DATA=$(gs_rest_get "styles/${EXPECTED_NAME}.json")
    STYLE_FOUND="true"
    STYLE_NAME="$EXPECTED_NAME"
    STYLE_FORMAT=$(echo "$STYLE_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('style',{}).get('format',''))" 2>/dev/null || echo "")

    # Get the SLD content and parse colors in context using Python XML parsing
    STYLE_SLD_CONTENT=$(gs_rest_get_xml "styles/${EXPECTED_NAME}.sld")
    COLOR_CHECK=$(echo "$STYLE_SLD_CONTENT" | python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    sld = sys.stdin.read()
    root = ET.fromstring(sld)
    # Handle SLD namespaces
    ns = {'sld': 'http://www.opengis.net/sld', 'ogc': 'http://www.opengis.net/ogc'}
    has_fill = False
    has_stroke = False
    # Search for CssParameter elements with fill/stroke names
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if tag == 'CssParameter':
            param_name = elem.get('name', '')
            text = (elem.text or '').strip().upper()
            if param_name == 'fill' and '0000FF' in text:
                has_fill = True
            elif param_name == 'stroke' and '000080' in text:
                has_stroke = True
    # Also check for Fill/Stroke elements with color children (SLD 1.1 style)
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if tag == 'Fill':
            for child in elem:
                child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if child_tag == 'CssParameter' and child.get('name') == 'fill':
                    if '0000FF' in (child.text or '').upper():
                        has_fill = True
        elif tag == 'Stroke':
            for child in elem:
                child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if child_tag == 'CssParameter' and child.get('name') == 'stroke':
                    if '000080' in (child.text or '').upper():
                        has_stroke = True
    print(f'{has_fill}|{has_stroke}')
except:
    # Fallback to simple grep if XML parsing fails
    has_fill = '0000ff' in sld.lower() or '0000FF' in sld
    has_stroke = '000080' in sld.lower()
    print(f'{has_fill}|{has_stroke}')
" 2>/dev/null || echo "False|False")
    FILL_RESULT=$(echo "$COLOR_CHECK" | cut -d'|' -f1)
    STROKE_RESULT=$(echo "$COLOR_CHECK" | cut -d'|' -f2)
    if [ "$FILL_RESULT" = "True" ]; then
        STYLE_HAS_FILL="true"
    fi
    if [ "$STROKE_RESULT" = "True" ]; then
        STYLE_HAS_STROKE="true"
    fi
fi

# If exact match fails, search all styles
if [ "$STYLE_FOUND" = "false" ]; then
    ALL_STYLES=$(gs_rest_get "styles.json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ss = d.get('styles', {}).get('style', [])
if not isinstance(ss, list):
    ss = [ss] if ss else []
for s in ss:
    print(s['name'])
" 2>/dev/null)

    for style_name in $ALL_STYLES; do
        style_lower=$(echo "$style_name" | tr '[:upper:]' '[:lower:]')
        if echo "$style_lower" | grep -q "blue.*polygon\|polygon.*blue\|blue_poly"; then
            STYLE_FOUND="true"
            STYLE_NAME="$style_name"
            STYLE_FORMAT=$(gs_rest_get "styles/${style_name}.json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('style',{}).get('format',''))" 2>/dev/null || echo "")

            STYLE_SLD_CONTENT=$(gs_rest_get_xml "styles/${style_name}.sld")
            PARTIAL_COLOR=$(echo "$STYLE_SLD_CONTENT" | python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    sld = sys.stdin.read()
    root = ET.fromstring(sld)
    has_fill = has_stroke = False
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if tag == 'CssParameter':
            name = elem.get('name', '')
            text = (elem.text or '').strip().upper()
            if name == 'fill' and '0000FF' in text: has_fill = True
            elif name == 'stroke' and '000080' in text: has_stroke = True
    print(f'{has_fill}|{has_stroke}')
except:
    print(f\"{'0000ff' in sld.lower()}|{'000080' in sld.lower()}\")
" 2>/dev/null || echo "False|False")
            if [ "$(echo "$PARTIAL_COLOR" | cut -d'|' -f1)" = "True" ]; then STYLE_HAS_FILL="true"; fi
            if [ "$(echo "$PARTIAL_COLOR" | cut -d'|' -f2)" = "True" ]; then STYLE_HAS_STROKE="true"; fi
            break
        fi
    done
fi

# If still not found, check any new style (only if count increased by 1-2)
if [ "$STYLE_FOUND" = "false" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ] && [ "$((CURRENT_COUNT - INITIAL_COUNT))" -le 2 ]; then
    NEWEST_STYLE=$(gs_rest_get "styles.json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ss = d.get('styles', {}).get('style', [])
if not isinstance(ss, list):
    ss = [ss] if ss else []
if ss:
    print(ss[-1]['name'])
" 2>/dev/null)
    if [ -n "$NEWEST_STYLE" ]; then
        STYLE_FOUND="true"
        STYLE_NAME="$NEWEST_STYLE"
        STYLE_SLD_CONTENT=$(gs_rest_get_xml "styles/${NEWEST_STYLE}.sld")
        NEWEST_COLOR=$(echo "$STYLE_SLD_CONTENT" | python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    sld = sys.stdin.read()
    root = ET.fromstring(sld)
    has_fill = has_stroke = False
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if tag == 'CssParameter':
            name = elem.get('name', '')
            text = (elem.text or '').strip().upper()
            if name == 'fill' and '0000FF' in text: has_fill = True
            elif name == 'stroke' and '000080' in text: has_stroke = True
    print(f'{has_fill}|{has_stroke}')
except:
    print(f\"{'0000ff' in sld.lower()}|{'000080' in sld.lower()}\")
" 2>/dev/null || echo "False|False")
        if [ "$(echo "$NEWEST_COLOR" | cut -d'|' -f1)" = "True" ]; then STYLE_HAS_FILL="true"; fi
        if [ "$(echo "$NEWEST_COLOR" | cut -d'|' -f2)" = "True" ]; then STYLE_HAS_STROKE="true"; fi
    fi
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_style_count": ${INITIAL_COUNT},
    "current_style_count": ${CURRENT_COUNT},
    "style_found": ${STYLE_FOUND},
    "style_name": "$(json_escape "$STYLE_NAME")",
    "style_format": "$(json_escape "$STYLE_FORMAT")",
    "style_has_fill": ${STYLE_HAS_FILL},
    "style_has_stroke": ${STYLE_HAS_STROKE},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_style_result.json"

echo "=== Export complete ==="
