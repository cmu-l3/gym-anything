#!/bin/bash
echo "=== Exporting create_labeled_choropleth_map result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Task Parameters
STYLE_NAME="population_choropleth"
WORKSPACE="ne"
LAYER_NAME="ne:ne_countries"
OUTPUT_FILE="/home/ga/output/population_map.png"

# 1. Check Output Image
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_VALID="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    # Check if it's a valid PNG and sufficiently large (not a 1x1 pixel error)
    if file "$OUTPUT_FILE" | grep -q "PNG image data" && [ "$OUTPUT_SIZE" -gt 1000 ]; then
        OUTPUT_VALID="true"
    fi
fi

# 2. Check Style Existence and Content
STYLE_FOUND="false"
STYLE_HAS_5_RULES="false"
STYLE_HAS_COLORS="false"
STYLE_HAS_TEXT="false"
STYLE_HAS_HALO="false"
STYLE_HAS_STROKE="false"
STYLE_SLD_CONTENT=""

# Check workspace specific style first: workspaces/ne/styles/population_choropleth
STYLE_STATUS=$(gs_rest_status "workspaces/${WORKSPACE}/styles/${STYLE_NAME}.json")
if [ "$STYLE_STATUS" = "200" ]; then
    STYLE_FOUND="true"
    # Get SLD content
    STYLE_SLD_CONTENT=$(gs_rest_get_xml "workspaces/${WORKSPACE}/styles/${STYLE_NAME}.sld")
else
    # Fallback: check global styles
    STYLE_STATUS=$(gs_rest_status "styles/${STYLE_NAME}.json")
    if [ "$STYLE_STATUS" = "200" ]; then
        STYLE_FOUND="true"
        STYLE_SLD_CONTENT=$(gs_rest_get_xml "styles/${STYLE_NAME}.sld")
    fi
fi

if [ "$STYLE_FOUND" = "true" ]; then
    # Analyze SLD content using Python for robustness
    SLD_ANALYSIS=$(echo "$STYLE_SLD_CONTENT" | python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    sld = sys.stdin.read()
    # Remove namespace prefixes for easier parsing or handle them
    # Simple strategy: ignore namespaces by stripping them in tags
    root = ET.fromstring(sld)
    
    rules = 0
    colors_found = set()
    has_text = False
    has_halo = False
    has_stroke = False
    
    target_colors = {'#ffffb2', '#fecc5c', '#fd8d3c', '#f03b20', '#bd0026'}
    
    # Iterate all elements
    for elem in root.iter():
        tag = elem.tag.split('}')[-1]
        
        if tag == 'Rule':
            rules += 1
            
        if tag == 'CssParameter':
            name = elem.get('name', '').lower()
            val = (elem.text or '').strip().lower()
            if name == 'fill' and val in target_colors:
                colors_found.add(val)
            if name == 'stroke' and '#999999' in val:
                has_stroke = True
                
        if tag == 'TextSymbolizer':
            has_text = True
            
        if tag == 'Halo':
            has_halo = True
            
    # Check if 5 unique target colors were found
    has_colors = len(colors_found) >= 5
    
    print(f'{rules}|{has_colors}|{has_text}|{has_halo}|{has_stroke}')
except Exception as e:
    print(f'0|False|False|False|False')
" 2>/dev/null)

    read -r RULE_COUNT HAS_COLORS HAS_TEXT HAS_HALO HAS_STROKE <<< "$(echo "$SLD_ANALYSIS" | tr '|' ' ')"
    
    if [ "$RULE_COUNT" -ge 5 ]; then STYLE_HAS_5_RULES="true"; fi
    if [ "$HAS_COLORS" = "True" ]; then STYLE_HAS_COLORS="true"; fi
    if [ "$HAS_TEXT" = "True" ]; then STYLE_HAS_TEXT="true"; fi
    if [ "$HAS_HALO" = "True" ]; then STYLE_HAS_HALO="true"; fi
    if [ "$HAS_STROKE" = "True" ]; then STYLE_HAS_STROKE="true"; fi
fi

# 3. Check Layer Default Style
LAYER_DEFAULT_STYLE=""
LAYER_DEFAULT_CORRECT="false"

LAYER_JSON=$(gs_rest_get "layers/${LAYER_NAME}.json")
if [ -n "$LAYER_JSON" ]; then
    # Extract default style name
    LAYER_DEFAULT_STYLE=$(echo "$LAYER_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null)
    
    # Check if it matches expected style (handle workspace prefix)
    if [ "$LAYER_DEFAULT_STYLE" = "$STYLE_NAME" ] || [ "$LAYER_DEFAULT_STYLE" = "${WORKSPACE}:${STYLE_NAME}" ]; then
        LAYER_DEFAULT_CORRECT="true"
    fi
fi

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": ${OUTPUT_EXISTS},
    "output_valid": ${OUTPUT_VALID},
    "output_size": ${OUTPUT_SIZE},
    "style_found": ${STYLE_FOUND},
    "style_rules_count": ${RULE_COUNT:-0},
    "style_has_colors": ${STYLE_HAS_COLORS},
    "style_has_text": ${STYLE_HAS_TEXT},
    "style_has_halo": ${STYLE_HAS_HALO},
    "style_has_stroke": ${STYLE_HAS_STROKE},
    "layer_default_style": "$(json_escape "$LAYER_DEFAULT_STYLE")",
    "layer_default_correct": ${LAYER_DEFAULT_CORRECT},
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "=== Export complete ==="