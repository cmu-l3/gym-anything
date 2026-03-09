#!/bin/bash
# Export script for wfs_feature_service_setup task

echo "=== Exporting wfs_feature_service_setup Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/wfs_feature_service_setup_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_LAYER_COUNT=$(cat /tmp/initial_layer_count 2>/dev/null || echo "0")
INITIAL_STYLE_COUNT=$(cat /tmp/initial_style_count 2>/dev/null || echo "0")
INITIAL_WFS_ENABLED=$(cat /tmp/initial_wfs_enabled 2>/dev/null || echo "false")
INITIAL_WFS_TITLE=$(cat /tmp/initial_wfs_title 2>/dev/null || echo "")
RESULT_NONCE=$(get_result_nonce)
GUI_INTERACTION=$(check_gui_interaction)

# ----- Check WFS service settings -----
WFS_JSON=$(gs_rest_get "services/wfs/settings.json" 2>/dev/null || echo "{}")
WFS_ENABLED=$(echo "$WFS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('wfs',{}).get('enabled',False)).lower())" 2>/dev/null || echo "false")
WFS_TITLE=$(echo "$WFS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wfs',{}).get('title',''))" 2>/dev/null || echo "")
WFS_ABSTRACT=$(echo "$WFS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wfs',{}).get('abstrct',''))" 2>/dev/null || echo "")
WFS_MAX=$(echo "$WFS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('wfs',{}).get('maxFeatures',0))" 2>/dev/null || echo "0")

# ----- Check SQL view layer major_cities in ne workspace -----
# The SQL view appears as a featuretype in the ne workspace (under the PostGIS datastore)
LAYER_FOUND=false
LAYER_NAME=""
LAYER_GEOM_TYPE=""

# Search for major_cities in all datastores of ne workspace
NE_DS_JSON=$(gs_rest_get "workspaces/ne/datastores.json" 2>/dev/null || echo "")
NE_DS_NAMES=$(echo "$NE_DS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stores = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(stores, list): stores = [stores] if stores else []
for s in stores:
    print(s.get('name',''))
" 2>/dev/null || echo "")

for DS_NAME in $NE_DS_NAMES; do
    FT_JSON=$(gs_rest_get "workspaces/ne/datastores/${DS_NAME}/featuretypes/major_cities.json" 2>/dev/null || echo "")
    if echo "$FT_JSON" | grep -q '"name"'; then
        LAYER_FOUND=true
        LAYER_NAME="major_cities"
        LAYER_GEOM_TYPE=$(echo "$FT_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
attrs = d.get('featureType', {}).get('attributes', {}).get('attribute', [])
if not isinstance(attrs, list): attrs = [attrs] if attrs else []
for a in attrs:
    t = a.get('binding', '').lower()
    n = a.get('name', '').lower()
    if 'geom' in n or 'wkb' in n or 'shape' in n or 'point' in t or 'geom' in t:
        print(t)
        break
" 2>/dev/null || echo "")
        break
    fi
done

# Also try direct featuretype endpoint (may not need datastore path)
if [ "$LAYER_FOUND" = "false" ]; then
    FT_DIRECT=$(gs_rest_get "workspaces/ne/featuretypes/major_cities.json" 2>/dev/null || echo "")
    if echo "$FT_DIRECT" | grep -q '"name"'; then
        LAYER_FOUND=true
        LAYER_NAME="major_cities"
        LAYER_GEOM_TYPE=$(echo "$FT_DIRECT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
attrs = d.get('featureType', {}).get('attributes', {}).get('attribute', [])
if not isinstance(attrs, list): attrs = [attrs] if attrs else []
for a in attrs:
    t = a.get('binding', '').lower()
    n = a.get('name', '').lower()
    if 'geom' in n or 'wkb' in n or 'point' in t or 'geom' in t:
        print(t)
        break
" 2>/dev/null || echo "")
    fi
fi

# Check if it's a point type
IS_POINT=false
if echo "$LAYER_GEOM_TYPE" | grep -qi "point"; then
    IS_POINT=true
fi

# ----- Check default style for ne:major_cities -----
MAJOR_CITIES_DEFAULT_STYLE=""
STYLE_MATCH=false
if [ "$LAYER_FOUND" = "true" ]; then
    LYR_JSON=$(gs_rest_get "layers/ne:major_cities.json" 2>/dev/null || echo "")
    MAJOR_CITIES_DEFAULT_STYLE=$(echo "$LYR_JSON" | python3 -c "
import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('defaultStyle',{}).get('name',''))
" 2>/dev/null || echo "")
    if echo "$MAJOR_CITIES_DEFAULT_STYLE" | grep -qi "city_marker\|city"; then
        STYLE_MATCH=true
    fi
fi

# ----- Check SLD city_marker -----
SLD_FOUND=false
SLD_HAS_CIRCLE=false
SLD_HAS_RED=false

# Try workspace-scoped first, then global
for SCOPE in "workspaces/ne/styles" "styles"; do
    SLD_STATUS=$(gs_rest_status "${SCOPE}/city_marker.json" 2>/dev/null || echo "404")
    if [ "$SLD_STATUS" = "200" ]; then
        SLD_FOUND=true
        SLD_CONTENT=$(gs_rest_get_xml "${SCOPE}/city_marker.sld" 2>/dev/null || echo "")

        if echo "$SLD_CONTENT" | grep -qi "circle\|WellKnownName.*circle"; then
            SLD_HAS_CIRCLE=true
        fi
        if echo "$SLD_CONTENT" | grep -qi "#FF0000\|#ff0000\|#F00\|red"; then
            SLD_HAS_RED=true
        fi
        break
    fi
done

CURRENT_LAYER_COUNT=$(get_layer_count)
CURRENT_STYLE_COUNT=$(get_style_count)

TMPFILE=$(mktemp /tmp/wfs_feature_service_setup_result_XXXXXX.json)
python3 << PYEOF
import json

result = {
    "result_nonce": "${RESULT_NONCE}",
    "task_start": ${TASK_START},
    "gui_interaction_detected": $([ "$GUI_INTERACTION" = "true" ] && echo "True" || echo "False"),

    "wfs_enabled": $([ "$WFS_ENABLED" = "true" ] && echo "True" || echo "False"),
    "wfs_title": "${WFS_TITLE}",
    "wfs_abstract": "${WFS_ABSTRACT}",
    "wfs_max_features": ${WFS_MAX:-0},
    "initial_wfs_enabled": $([ "$INITIAL_WFS_ENABLED" = "true" ] && echo "True" || echo "False"),

    "layer_found": $([ "$LAYER_FOUND" = "true" ] && echo "True" || echo "False"),
    "layer_name": "${LAYER_NAME}",
    "layer_geom_type": "${LAYER_GEOM_TYPE}",
    "is_point": $([ "$IS_POINT" = "true" ] && echo "True" || echo "False"),

    "major_cities_default_style": "${MAJOR_CITIES_DEFAULT_STYLE}",
    "style_match": $([ "$STYLE_MATCH" = "true" ] && echo "True" || echo "False"),

    "sld_found": $([ "$SLD_FOUND" = "true" ] && echo "True" || echo "False"),
    "sld_has_circle": $([ "$SLD_HAS_CIRCLE" = "true" ] && echo "True" || echo "False"),
    "sld_has_red": $([ "$SLD_HAS_RED" = "true" ] && echo "True" || echo "False"),

    "initial_layer_count": ${INITIAL_LAYER_COUNT},
    "current_layer_count": ${CURRENT_LAYER_COUNT},
    "initial_style_count": ${INITIAL_STYLE_COUNT},
    "current_style_count": ${CURRENT_STYLE_COUNT}
}

with open("${TMPFILE}", "w") as f:
    json.dump(result, f, indent=2)
print("Result written")
PYEOF

safe_write_result "$TMPFILE" "/tmp/wfs_feature_service_setup_result.json"

echo "=== Export Complete ==="
