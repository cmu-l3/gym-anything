#!/bin/bash
echo "=== Exporting assign_alternate_styles result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Files to check
POP_MAP="/home/ga/output/map_population.png"
ECON_MAP="/home/ga/output/map_economy.png"

# Check output files
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local size=$(stat -c%s "$f")
        local mtime=$(stat -c%Y "$f")
        echo "true|$size|$mtime"
    else
        echo "false|0|0"
    fi
}

POP_Check=$(check_file "$POP_MAP")
ECON_Check=$(check_file "$ECON_MAP")

# Compare images (simple difference check)
IMAGES_DIFFER="false"
if [ -f "$POP_MAP" ] && [ -f "$ECON_MAP" ]; then
    if ! cmp -s "$POP_MAP" "$ECON_MAP"; then
        IMAGES_DIFFER="true"
    fi
fi

# Check Style 1: population_classes
STYLE1_NAME="population_classes"
STYLE1_EXISTS="false"
STYLE1_SLD=""
if [ "$(gs_rest_status "workspaces/ne/styles/$STYLE1_NAME.json")" = "200" ]; then
    STYLE1_EXISTS="true"
    STYLE1_SLD=$(gs_rest_get_xml "workspaces/ne/styles/$STYLE1_NAME.sld")
elif [ "$(gs_rest_status "styles/$STYLE1_NAME.json")" = "200" ]; then
    STYLE1_EXISTS="true"
    STYLE1_SLD=$(gs_rest_get_xml "styles/$STYLE1_NAME.sld")
fi

# Check Style 2: economy_types
STYLE2_NAME="economy_types"
STYLE2_EXISTS="false"
STYLE2_SLD=""
if [ "$(gs_rest_status "workspaces/ne/styles/$STYLE2_NAME.json")" = "200" ]; then
    STYLE2_EXISTS="true"
    STYLE2_SLD=$(gs_rest_get_xml "workspaces/ne/styles/$STYLE2_NAME.sld")
elif [ "$(gs_rest_status "styles/$STYLE2_NAME.json")" = "200" ]; then
    STYLE2_EXISTS="true"
    STYLE2_SLD=$(gs_rest_get_xml "styles/$STYLE2_NAME.sld")
fi

# Check Layer Association (ne:ne_countries)
LAYER_STYLES_JSON=$(gs_rest_get "layers/ne:ne_countries.json")
# Extract styles list. Structure: layer -> styles -> style -> [ {name: ...}, ... ]
ASSOCIATED_STYLES=$(echo "$LAYER_STYLES_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    styles = d.get('layer', {}).get('styles', {}).get('style', [])
    if isinstance(styles, dict): styles = [styles]
    names = [s.get('name') for s in styles]
    print(','.join(filter(None, names)))
except: print('')
" 2>/dev/null)

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "pop_map_exists": $(echo "$POP_Check" | cut -d'|' -f1),
    "pop_map_size": $(echo "$POP_Check" | cut -d'|' -f2),
    "pop_map_mtime": $(echo "$POP_Check" | cut -d'|' -f3),
    "econ_map_exists": $(echo "$ECON_Check" | cut -d'|' -f1),
    "econ_map_size": $(echo "$ECON_Check" | cut -d'|' -f2),
    "econ_map_mtime": $(echo "$ECON_Check" | cut -d'|' -f3),
    "images_differ": $IMAGES_DIFFER,
    "style1_exists": $STYLE1_EXISTS,
    "style1_sld": "$(json_escape "$STYLE1_SLD")",
    "style2_exists": $STYLE2_EXISTS,
    "style2_sld": "$(json_escape "$STYLE2_SLD")",
    "associated_styles": "$(json_escape "$ASSOCIATED_STYLES")",
    "gui_interaction": $GUI_INTERACTION,
    "task_start_time": $TASK_START,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/assign_alternate_styles_result.json"

echo "=== Export complete ==="