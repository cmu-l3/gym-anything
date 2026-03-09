#!/bin/bash
echo "=== Exporting style_point_clustering result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Get verification data
EXPECTED_STYLE="clustered_places"
EXPECTED_LAYER="ne:ne_populated_places"

# A. Check Layer Configuration (Default Style)
LAYER_DATA=$(gs_rest_get "layers/${EXPECTED_LAYER}.json")
CURRENT_DEFAULT_STYLE=$(echo "$LAYER_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null || echo "")

# B. Check Style Existence and Content
# Try direct match
STYLE_SLD=""
STYLE_FOUND="false"
STYLE_NAME_FOUND=""

# Check global or workspace specific
if [ "$(gs_rest_status "styles/${EXPECTED_STYLE}.sld")" = "200" ]; then
    STYLE_SLD=$(gs_rest_get_xml "styles/${EXPECTED_STYLE}.sld")
    STYLE_FOUND="true"
    STYLE_NAME_FOUND="${EXPECTED_STYLE}"
elif [ "$(gs_rest_status "workspaces/ne/styles/${EXPECTED_STYLE}.sld")" = "200" ]; then
    STYLE_SLD=$(gs_rest_get_xml "workspaces/ne/styles/${EXPECTED_STYLE}.sld")
    STYLE_FOUND="true"
    STYLE_NAME_FOUND="ne:${EXPECTED_STYLE}"
else
    # Fallback: Search all styles if they named it slightly differently
    ALL_STYLES=$(gs_rest_get "styles.json" | python3 -c "import sys,json; [print(s['name']) for s in json.load(sys.stdin).get('styles',{}).get('style',[])]" 2>/dev/null)
    for s in $ALL_STYLES; do
        if [[ "${s,,}" == *"clustered"* && "${s,,}" == *"places"* ]]; then
            STYLE_SLD=$(gs_rest_get_xml "styles/${s}.sld")
            STYLE_FOUND="true"
            STYLE_NAME_FOUND="$s"
            break
        fi
    done
fi

# C. Check GUI Interaction
GUI_INTERACTION=$(check_gui_interaction)

# D. Create Python script to safely generate JSON output
# We use python to create the JSON to handle proper escaping of the XML SLD content
python3 -c "
import json
import os
import sys

try:
    data = {
        'timestamp': '$(date -Iseconds)',
        'task_start': $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
        'initial_default_style': '$(cat /tmp/initial_default_style.txt 2>/dev/null)',
        'current_default_style': '$CURRENT_DEFAULT_STYLE',
        'style_found': '$STYLE_FOUND' == 'true',
        'style_name_found': '$STYLE_NAME_FOUND',
        'style_sld_content': sys.stdin.read(),
        'gui_interaction': '$GUI_INTERACTION' == 'true',
        'result_nonce': '$(get_result_nonce)'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f)
        
except Exception as e:
    print(f'Error generating JSON: {e}', file=sys.stderr)
" <<< "$STYLE_SLD"

# Safe copy result
rm -f /tmp/style_clustering_result.json 2>/dev/null || true
cp /tmp/task_result.json /tmp/style_clustering_result.json
chmod 666 /tmp/style_clustering_result.json 2>/dev/null || true

echo "Result saved to /tmp/style_clustering_result.json"
echo "=== Export complete ==="