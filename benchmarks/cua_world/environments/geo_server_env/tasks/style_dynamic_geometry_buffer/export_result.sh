#!/bin/bash
echo "=== Exporting style_dynamic_geometry_buffer result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read initial state
INITIAL_STYLE_COUNT=$(cat /tmp/initial_style_count 2>/dev/null || echo "0")
CURRENT_STYLE_COUNT=$(get_style_count)

EXPECTED_STYLE="river_buffer"
STYLE_FOUND="false"
STYLE_CONTENT=""
STYLE_HAS_BUFFER="false"
STYLE_HAS_POLYGON="false"
STYLE_DISTANCE_CORRECT="false"
STYLE_COLOR_CORRECT="false"
STYLE_OPACITY_CORRECT="false"

# Check if style exists
STYLE_STATUS=$(gs_rest_status "styles/${EXPECTED_STYLE}.json")
if [ "$STYLE_STATUS" != "200" ]; then
    # Try workspace specific
    STYLE_STATUS=$(gs_rest_status "workspaces/ne/styles/${EXPECTED_STYLE}.json")
    if [ "$STYLE_STATUS" = "200" ]; then
        STYLE_CONTENT=$(gs_rest_get_xml "workspaces/ne/styles/${EXPECTED_STYLE}.sld")
        STYLE_FOUND="true"
    fi
else
    STYLE_CONTENT=$(gs_rest_get_xml "styles/${EXPECTED_STYLE}.sld")
    STYLE_FOUND="true"
fi

# Analyze SLD content using Python for robustness
if [ "$STYLE_FOUND" = "true" ]; then
    ANALYSIS=$(echo "$STYLE_CONTENT" | python3 -c "
import sys, re
sld = sys.stdin.read().lower()

# Check for PolygonSymbolizer
has_poly = 'polygonsymbolizer' in sld

# Check for buffer function (ogc:Function name='buffer' or similar)
# We look for 'buffer' and 'function' in close proximity or simple string check
has_buffer = 'function' in sld and 'buffer' in sld

# Check distance 0.1
# Look for Literal 0.1 inside geometry/function context roughly
dist_correct = '0.1' in sld

# Check color #FF0000
color_correct = '#ff0000' in sld

# Check opacity 0.5
opacity_correct = '0.5' in sld and ('fill-opacity' in sld or 'opacity' in sld)

print(f'{has_poly}|{has_buffer}|{dist_correct}|{color_correct}|{opacity_correct}')
" 2>/dev/null || echo "False|False|False|False|False")

    STYLE_HAS_POLYGON=$(echo "$ANALYSIS" | cut -d'|' -f1)
    STYLE_HAS_BUFFER=$(echo "$ANALYSIS" | cut -d'|' -f2)
    STYLE_DISTANCE_CORRECT=$(echo "$ANALYSIS" | cut -d'|' -f3)
    STYLE_COLOR_CORRECT=$(echo "$ANALYSIS" | cut -d'|' -f4)
    STYLE_OPACITY_CORRECT=$(echo "$ANALYSIS" | cut -d'|' -f5)
fi

# Check Layer Assignment
LAYER_ASSIGNED="false"
LAYER_INFO=$(gs_rest_get "workspaces/ne/layers/ne_rivers.json")
ASSIGNMENT_CHECK=$(echo "$LAYER_INFO" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    layer = d.get('layer', {})
    def_style = layer.get('defaultStyle', {}).get('name', '')
    styles = [s.get('name') for s in layer.get('styles', {}).get('style', [])]
    
    target = '${EXPECTED_STYLE}'
    target_ws = 'ne:${EXPECTED_STYLE}'
    
    if target in def_style or target_ws in def_style:
        print('True')
    elif any(target in s or target_ws in s for s in styles):
        print('True')
    else:
        print('False')
except:
    print('False')
" 2>/dev/null || echo "False")

if [ "$ASSIGNMENT_CHECK" = "True" ]; then
    LAYER_ASSIGNED="true"
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_style_count": ${INITIAL_STYLE_COUNT},
    "current_style_count": ${CURRENT_STYLE_COUNT},
    "style_found": ${STYLE_FOUND},
    "style_has_polygon": ${STYLE_HAS_POLYGON},
    "style_has_buffer": ${STYLE_HAS_BUFFER},
    "style_distance_correct": ${STYLE_DISTANCE_CORRECT},
    "style_color_correct": ${STYLE_COLOR_CORRECT},
    "style_opacity_correct": ${STYLE_OPACITY_CORRECT},
    "layer_assigned": ${LAYER_ASSIGNED},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/style_dynamic_geometry_buffer_result.json"

echo "=== Export complete ==="