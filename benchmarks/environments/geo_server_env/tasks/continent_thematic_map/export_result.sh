#!/bin/bash
# Export script for continent_thematic_map task

echo "=== Exporting continent_thematic_map Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/continent_thematic_map_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_WORKSPACE_COUNT=$(cat /tmp/initial_workspace_count 2>/dev/null || echo "0")
INITIAL_LAYER_COUNT=$(cat /tmp/initial_layer_count 2>/dev/null || echo "0")
INITIAL_STYLE_COUNT=$(cat /tmp/initial_style_count 2>/dev/null || echo "0")
RESULT_NONCE=$(get_result_nonce)
GUI_INTERACTION=$(check_gui_interaction)

# ----- Check workspace -----
WS_JSON=$(gs_rest_get "workspaces/regional_atlas.json" 2>/dev/null || echo "")
WS_FOUND=false
WS_NAME=""
if echo "$WS_JSON" | grep -q '"name"'; then
    WS_FOUND=true
    WS_NAME=$(echo "$WS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('workspace',{}).get('name',''))" 2>/dev/null || echo "regional_atlas")
fi

# ----- Check datastores in regional_atlas -----
DS_JSON=$(gs_rest_get "workspaces/regional_atlas/datastores.json" 2>/dev/null || echo "")
DS_FOUND=false
DS_NAME=""
DS_TYPE=""
if echo "$DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
print(len(stores))
" 2>/dev/null | grep -qv '^0$'; then
    DS_FOUND=true
    DS_INFO=$(echo "$DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
for s in stores:
    print(s.get('name','') + '|postgis')
" 2>/dev/null | head -1)
    DS_NAME=$(echo "$DS_INFO" | cut -d'|' -f1)
    DS_TYPE=$(echo "$DS_INFO" | cut -d'|' -f2)
fi

# Check if it's actually a PostGIS type store
if [ "$DS_FOUND" = "true" ] && [ -n "$DS_NAME" ]; then
    DS_DETAIL=$(gs_rest_get "workspaces/regional_atlas/datastores/${DS_NAME}.json" 2>/dev/null || echo "")
    if echo "$DS_DETAIL" | grep -qi "postgis\|PostGIS"; then
        DS_TYPE="postgis"
    fi
fi

# ----- Check layer 'countries' in regional_atlas -----
LAYER_FOUND=false
LAYER_NAME=""
LAYER_WS=""
LAYER_SRS=""

# Try exact name first
FT_JSON=$(gs_rest_get "workspaces/regional_atlas/featuretypes/countries.json" 2>/dev/null || echo "")
if echo "$FT_JSON" | grep -q '"name"'; then
    LAYER_FOUND=true
    LAYER_NAME="countries"
    LAYER_WS="regional_atlas"
    LAYER_SRS=$(echo "$FT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('featureType',{}).get('srs',''))" 2>/dev/null || echo "")
else
    # Try to find any layer with 'countr' in the name in regional_atlas
    if [ "$DS_FOUND" = "true" ] && [ -n "$DS_NAME" ]; then
        FTS_JSON=$(gs_rest_get "workspaces/regional_atlas/datastores/${DS_NAME}/featuretypes.json" 2>/dev/null || echo "")
        LAYER_NAME=$(echo "$FTS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
fts = d.get('featureTypes', {}).get('featureType', [])
if not isinstance(fts, list): fts = [fts] if fts else []
for ft in fts:
    n = ft.get('name','').lower()
    if 'countr' in n or 'countries' in n or 'ne_countries' in n:
        print(ft.get('name',''))
        break
" 2>/dev/null || echo "")
        if [ -n "$LAYER_NAME" ]; then
            LAYER_FOUND=true
            LAYER_WS="regional_atlas"
        fi
    fi
fi

# ----- Check default style for the layer -----
DEFAULT_STYLE=""
DEFAULT_STYLE_MATCH=false
if [ "$LAYER_FOUND" = "true" ] && [ -n "$LAYER_NAME" ]; then
    LAYER_INFO=$(gs_rest_get "layers/regional_atlas:${LAYER_NAME}.json" 2>/dev/null || echo "")
    DEFAULT_STYLE=$(echo "$LAYER_INFO" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))
" 2>/dev/null || echo "")
    if echo "$DEFAULT_STYLE" | grep -qi "continent_colors\|continent"; then
        DEFAULT_STYLE_MATCH=true
    fi
fi

# ----- Check SLD style 'continent_colors' (workspace or global) -----
SLD_FOUND=false
SLD_CONTENT=""
SLD_RULE_COUNT=0
SLD_HAS_CONTINENT_FILTER=false
SLD_DISTINCT_COLORS=0

# Try workspace-scoped style first
SLD_CHECK=$(gs_rest_status "workspaces/regional_atlas/styles/continent_colors.json" 2>/dev/null || echo "404")
if [ "$SLD_CHECK" = "200" ]; then
    SLD_FOUND=true
    SLD_CONTENT=$(gs_rest_get_xml "workspaces/regional_atlas/styles/continent_colors.sld" 2>/dev/null || echo "")
else
    # Try global style
    SLD_CHECK2=$(gs_rest_status "styles/continent_colors.json" 2>/dev/null || echo "404")
    if [ "$SLD_CHECK2" = "200" ]; then
        SLD_FOUND=true
        SLD_CONTENT=$(gs_rest_get_xml "styles/continent_colors.sld" 2>/dev/null || echo "")
    fi
fi

# Parse SLD content with Python
if [ "$SLD_FOUND" = "true" ] && [ -n "$SLD_CONTENT" ]; then
    SLD_ANALYSIS=$(echo "$SLD_CONTENT" | python3 << 'PYEOF'
import sys, re

content = sys.stdin.read()

# Count Rule elements
rule_count = len(re.findall(r'<Rule\b', content, re.IGNORECASE))

# Check for continent property in filter expressions
has_continent = bool(re.search(r'<ogc:PropertyName[^>]*>\s*continent\s*</ogc:PropertyName>', content, re.IGNORECASE))

# Extract all distinct hex fill colors
fill_colors = set()
for m in re.finditer(r'<CssParameter\s+name=["\']fill["\'][^>]*>\s*(#[0-9A-Fa-f]{6})\s*</CssParameter>', content):
    fill_colors.add(m.group(1).upper())

print(f"rules={rule_count}")
print(f"continent_filter={'true' if has_continent else 'false'}")
print(f"distinct_colors={len(fill_colors)}")
print(f"colors={'|'.join(sorted(fill_colors))}")
PYEOF
)
    SLD_RULE_COUNT=$(echo "$SLD_ANALYSIS" | grep '^rules=' | cut -d= -f2)
    SLD_HAS_CONTINENT=$(echo "$SLD_ANALYSIS" | grep '^continent_filter=' | cut -d= -f2)
    SLD_DISTINCT_COLORS=$(echo "$SLD_ANALYSIS" | grep '^distinct_colors=' | cut -d= -f2)
    SLD_COLORS=$(echo "$SLD_ANALYSIS" | grep '^colors=' | cut -d= -f2)

    [ "$SLD_HAS_CONTINENT" = "true" ] && SLD_HAS_CONTINENT_FILTER=true || SLD_HAS_CONTINENT_FILTER=false
fi

# ----- Count current entities -----
CURRENT_WORKSPACE_COUNT=$(get_workspace_count)
CURRENT_LAYER_COUNT=$(get_layer_count)
CURRENT_STYLE_COUNT=$(get_style_count)

# ----- Write result JSON -----
TMPFILE=$(mktemp /tmp/continent_thematic_map_result_XXXXXX.json)
python3 << PYEOF
import json

result = {
    "result_nonce": "${RESULT_NONCE}",
    "task_start": ${TASK_START},
    "gui_interaction_detected": $([ "$GUI_INTERACTION" = "true" ] && echo "True" || echo "False"),

    "workspace_found": $([ "$WS_FOUND" = "true" ] && echo "True" || echo "False"),
    "workspace_name": "${WS_NAME}",

    "datastore_found": $([ "$DS_FOUND" = "true" ] && echo "True" || echo "False"),
    "datastore_name": "${DS_NAME}",
    "datastore_type": "${DS_TYPE}",

    "layer_found": $([ "$LAYER_FOUND" = "true" ] && echo "True" || echo "False"),
    "layer_name": "${LAYER_NAME}",
    "layer_workspace": "${LAYER_WS}",
    "layer_srs": "${LAYER_SRS}",

    "default_style": "${DEFAULT_STYLE}",
    "default_style_match": $([ "$DEFAULT_STYLE_MATCH" = "true" ] && echo "True" || echo "False"),

    "sld_found": $([ "$SLD_FOUND" = "true" ] && echo "True" || echo "False"),
    "sld_rule_count": ${SLD_RULE_COUNT:-0},
    "sld_has_continent_filter": $([ "$SLD_HAS_CONTINENT_FILTER" = "true" ] && echo "True" || echo "False"),
    "sld_distinct_colors": ${SLD_DISTINCT_COLORS:-0},
    "sld_colors": "${SLD_COLORS}",

    "initial_workspace_count": ${INITIAL_WORKSPACE_COUNT},
    "current_workspace_count": ${CURRENT_WORKSPACE_COUNT},
    "initial_layer_count": ${INITIAL_LAYER_COUNT},
    "current_layer_count": ${CURRENT_LAYER_COUNT},
    "initial_style_count": ${INITIAL_STYLE_COUNT},
    "current_style_count": ${CURRENT_STYLE_COUNT}
}

with open("${TMPFILE}", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written successfully")
PYEOF

safe_write_result "$TMPFILE" "/tmp/continent_thematic_map_result.json"

echo "=== Export Complete ==="
