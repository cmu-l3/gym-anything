#!/bin/bash
# Export script for multi_workspace_portal task

echo "=== Exporting multi_workspace_portal Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/multi_workspace_portal_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_NONCE=$(get_result_nonce)
GUI_INTERACTION=$(check_gui_interaction)

# ----- Check workspace infrastructure -----
INFRA_WS=$(gs_rest_get "workspaces/infrastructure.json" 2>/dev/null || echo "")
INFRA_FOUND=$(echo "$INFRA_WS" | grep -q '"name"' && echo "True" || echo "False")

# ----- Check workspace environment -----
ENV_WS=$(gs_rest_get "workspaces/environment.json" 2>/dev/null || echo "")
ENV_FOUND=$(echo "$ENV_WS" | grep -q '"name"' && echo "True" || echo "False")

# ----- Check datastores -----
INFRA_DS_JSON=$(gs_rest_get "workspaces/infrastructure/datastores.json" 2>/dev/null || echo "")
INFRA_DS_FOUND=$(echo "$INFRA_DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
print('true' if len(stores) > 0 else 'false')
" 2>/dev/null || echo "false")

ENV_DS_JSON=$(gs_rest_get "workspaces/environment/datastores.json" 2>/dev/null || echo "")
ENV_DS_FOUND=$(echo "$ENV_DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
print('true' if len(stores) > 0 else 'false')
" 2>/dev/null || echo "false")

# ----- Check layer settlements in infrastructure -----
SETTLEMENTS_FOUND=false
SETTLEMENTS_SRS=""
# Try exact name
FT=$(gs_rest_get "workspaces/infrastructure/featuretypes/settlements.json" 2>/dev/null || echo "")
if echo "$FT" | grep -q '"name"'; then
    SETTLEMENTS_FOUND=true
    SETTLEMENTS_SRS=$(echo "$FT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('featureType',{}).get('srs',''))" 2>/dev/null || echo "")
else
    # Search all datastores in infrastructure
    INFRA_DS_NAMES=$(echo "$INFRA_DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
for s in stores: print(s.get('name',''))
" 2>/dev/null || echo "")
    for DS_NAME in $INFRA_DS_NAMES; do
        FTS=$(gs_rest_get "workspaces/infrastructure/datastores/${DS_NAME}/featuretypes.json" 2>/dev/null || echo "")
        FOUND_LAYER=$(echo "$FTS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
fts = d.get('featureTypes', {}).get('featureType', [])
if not isinstance(fts, list): fts = [fts] if fts else []
for ft in fts:
    n = ft.get('name','').lower()
    if 'settl' in n or 'populated' in n or 'places' in n or 'cities' in n:
        print(ft.get('name',''))
        break
" 2>/dev/null || echo "")
        if [ -n "$FOUND_LAYER" ]; then
            SETTLEMENTS_FOUND=true
            break
        fi
    done
fi

# ----- Check layer waterways in environment -----
WATERWAYS_FOUND=false
WATERWAYS_SRS=""
FT=$(gs_rest_get "workspaces/environment/featuretypes/waterways.json" 2>/dev/null || echo "")
if echo "$FT" | grep -q '"name"'; then
    WATERWAYS_FOUND=true
    WATERWAYS_SRS=$(echo "$FT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('featureType',{}).get('srs',''))" 2>/dev/null || echo "")
else
    # Search all datastores in environment
    ENV_DS_NAMES=$(echo "$ENV_DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
for s in stores: print(s.get('name',''))
" 2>/dev/null || echo "")
    for DS_NAME in $ENV_DS_NAMES; do
        FTS=$(gs_rest_get "workspaces/environment/datastores/${DS_NAME}/featuretypes.json" 2>/dev/null || echo "")
        FOUND_LAYER=$(echo "$FTS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
fts = d.get('featureTypes', {}).get('featureType', [])
if not isinstance(fts, list): fts = [fts] if fts else []
for ft in fts:
    n = ft.get('name','').lower()
    if 'water' in n or 'river' in n or 'stream' in n or 'waterway' in n:
        print(ft.get('name',''))
        break
" 2>/dev/null || echo "")
        if [ -n "$FOUND_LAYER" ]; then
            WATERWAYS_FOUND=true
            break
        fi
    done
fi

# ----- Check default styles -----
SETTLEMENTS_DEFAULT_STYLE=""
WATERWAYS_DEFAULT_STYLE=""
SETTLEMENTS_STYLE_MATCH=false
WATERWAYS_STYLE_MATCH=false

if [ "$SETTLEMENTS_FOUND" = "true" ]; then
    LYR=$(gs_rest_get "layers/infrastructure:settlements.json" 2>/dev/null || echo "")
    SETTLEMENTS_DEFAULT_STYLE=$(echo "$LYR" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null || echo "")
    echo "$SETTLEMENTS_DEFAULT_STYLE" | grep -qi "settlement_marker\|settlement\|marker" && SETTLEMENTS_STYLE_MATCH=true
fi

if [ "$WATERWAYS_FOUND" = "true" ]; then
    LYR=$(gs_rest_get "layers/environment:waterways.json" 2>/dev/null || echo "")
    WATERWAYS_DEFAULT_STYLE=$(echo "$LYR" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))" 2>/dev/null || echo "")
    echo "$WATERWAYS_DEFAULT_STYLE" | grep -qi "waterway_line\|waterway\|line\|blue" && WATERWAYS_STYLE_MATCH=true
fi

# ----- Check SLD settlement_marker -----
SM_FOUND=false
SM_HAS_CIRCLE=false
SM_HAS_ORANGE=false
for SCOPE in "styles" "workspaces/infrastructure/styles"; do
    SM_STATUS=$(gs_rest_status "${SCOPE}/settlement_marker.json" 2>/dev/null || echo "404")
    if [ "$SM_STATUS" = "200" ]; then
        SM_FOUND=true
        SM_SLD=$(gs_rest_get_xml "${SCOPE}/settlement_marker.sld" 2>/dev/null || echo "")
        echo "$SM_SLD" | grep -qi "circle\|WellKnownName" && SM_HAS_CIRCLE=true
        echo "$SM_SLD" | grep -qi "#FFA500\|#ffa500\|orange" && SM_HAS_ORANGE=true
        break
    fi
done

# ----- Check SLD waterway_line -----
WL_FOUND=false
WL_HAS_LINE=false
WL_HAS_BLUE=false
for SCOPE in "styles" "workspaces/environment/styles"; do
    WL_STATUS=$(gs_rest_status "${SCOPE}/waterway_line.json" 2>/dev/null || echo "404")
    if [ "$WL_STATUS" = "200" ]; then
        WL_FOUND=true
        WL_SLD=$(gs_rest_get_xml "${SCOPE}/waterway_line.sld" 2>/dev/null || echo "")
        echo "$WL_SLD" | grep -qi "LineSymbolizer\|LineString" && WL_HAS_LINE=true
        echo "$WL_SLD" | grep -qi "#0080FF\|#0080ff\|#0000FF\|blue" && WL_HAS_BLUE=true
        break
    fi
done

# ----- Check layer group regional_portal -----
LG_JSON=$(gs_rest_get "layergroups/regional_portal.json" 2>/dev/null || echo "")
LG_FOUND=false
LG_LAYER_COUNT=0
LG_HAS_SETTLEMENTS=false
LG_HAS_WATERWAYS=false

if echo "$LG_JSON" | grep -q '"name"'; then
    LG_FOUND=true
    LG_ANALYSIS=$(echo "$LG_JSON" | python3 << 'PYEOF'
import sys, json
d = json.load(sys.stdin)
lg = d.get('layerGroup', {})
pub = lg.get('publishables', {}).get('published', [])
if not isinstance(pub, list): pub = [pub] if pub else []
layer_names = []
for p in pub:
    if isinstance(p, dict):
        href = p.get('href','')
        name = p.get('name','')
        if not name and href:
            name = href.split('/')[-1].replace('.json','')
        layer_names.append(name.lower())
print(f"count={len(layer_names)}")
has_settle = any('settlement' in n or 'populated' in n or 'cities' in n or 'places' in n for n in layer_names)
has_water = any('waterway' in n or 'river' in n or 'water' in n for n in layer_names)
print(f"has_settlements={'true' if has_settle else 'false'}")
print(f"has_waterways={'true' if has_water else 'false'}")
print(f"layers={'|'.join(layer_names)}")
PYEOF
)
    LG_LAYER_COUNT=$(echo "$LG_ANALYSIS" | grep '^count=' | cut -d= -f2)
    LG_HAS_SETTLEMENTS=$(echo "$LG_ANALYSIS" | grep '^has_settlements=' | cut -d= -f2)
    LG_HAS_WATERWAYS=$(echo "$LG_ANALYSIS" | grep '^has_waterways=' | cut -d= -f2)
    LG_LAYERS=$(echo "$LG_ANALYSIS" | grep '^layers=' | cut -d= -f2)
fi

CURRENT_WORKSPACE_COUNT=$(get_workspace_count)
CURRENT_LAYER_COUNT=$(get_layer_count)
CURRENT_STYLE_COUNT=$(get_style_count)
CURRENT_LG_COUNT=$(get_layergroup_count)

TMPFILE=$(mktemp /tmp/multi_workspace_portal_result_XXXXXX.json)
python3 << PYEOF
import json

result = {
    "result_nonce": "${RESULT_NONCE}",
    "task_start": ${TASK_START},
    "gui_interaction_detected": $([ "$GUI_INTERACTION" = "true" ] && echo "True" || echo "False"),

    "infra_workspace_found": $([ "$INFRA_FOUND" = "true" ] && echo "True" || echo "False"),
    "env_workspace_found": $([ "$ENV_FOUND" = "true" ] && echo "True" || echo "False"),
    "infra_datastore_found": $([ "$INFRA_DS_FOUND" = "true" ] && echo "True" || echo "False"),
    "env_datastore_found": $([ "$ENV_DS_FOUND" = "true" ] && echo "True" || echo "False"),

    "settlements_found": $([ "$SETTLEMENTS_FOUND" = "true" ] && echo "True" || echo "False"),
    "settlements_srs": "${SETTLEMENTS_SRS}",
    "waterways_found": $([ "$WATERWAYS_FOUND" = "true" ] && echo "True" || echo "False"),
    "waterways_srs": "${WATERWAYS_SRS}",

    "settlements_default_style": "${SETTLEMENTS_DEFAULT_STYLE}",
    "waterways_default_style": "${WATERWAYS_DEFAULT_STYLE}",
    "settlements_style_match": $([ "$SETTLEMENTS_STYLE_MATCH" = "true" ] && echo "True" || echo "False"),
    "waterways_style_match": $([ "$WATERWAYS_STYLE_MATCH" = "true" ] && echo "True" || echo "False"),

    "settlement_marker_found": $([ "$SM_FOUND" = "true" ] && echo "True" || echo "False"),
    "settlement_marker_has_circle": $([ "$SM_HAS_CIRCLE" = "true" ] && echo "True" || echo "False"),
    "settlement_marker_has_orange": $([ "$SM_HAS_ORANGE" = "true" ] && echo "True" || echo "False"),
    "waterway_line_found": $([ "$WL_FOUND" = "true" ] && echo "True" || echo "False"),
    "waterway_line_has_line": $([ "$WL_HAS_LINE" = "true" ] && echo "True" || echo "False"),
    "waterway_line_has_blue": $([ "$WL_HAS_BLUE" = "true" ] && echo "True" || echo "False"),

    "layer_group_found": $([ "$LG_FOUND" = "true" ] && echo "True" || echo "False"),
    "layer_group_layer_count": ${LG_LAYER_COUNT:-0},
    "layer_group_has_settlements": $([ "$LG_HAS_SETTLEMENTS" = "true" ] && echo "True" || echo "False"),
    "layer_group_has_waterways": $([ "$LG_HAS_WATERWAYS" = "true" ] && echo "True" || echo "False"),
    "layer_group_layers": "${LG_LAYERS}",

    "initial_workspace_count": $(cat /tmp/initial_workspace_count 2>/dev/null || echo "0"),
    "current_workspace_count": ${CURRENT_WORKSPACE_COUNT},
    "initial_layer_count": $(cat /tmp/initial_layer_count 2>/dev/null || echo "0"),
    "current_layer_count": ${CURRENT_LAYER_COUNT},
    "initial_style_count": $(cat /tmp/initial_style_count 2>/dev/null || echo "0"),
    "current_style_count": ${CURRENT_STYLE_COUNT},
    "initial_lg_count": $(cat /tmp/initial_lg_count 2>/dev/null || echo "0"),
    "current_lg_count": ${CURRENT_LG_COUNT}
}

with open("${TMPFILE}", "w") as f:
    json.dump(result, f, indent=2)
print("Result written")
PYEOF

safe_write_result "$TMPFILE" "/tmp/multi_workspace_portal_result.json"

echo "=== Export Complete ==="
