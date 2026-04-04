#!/bin/bash
echo "=== Exporting publish_shapefile_layer result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read initial state
INITIAL_LAYER_COUNT=$(cat /tmp/initial_layer_count 2>/dev/null || echo "0")
INITIAL_STORE_COUNT=$(cat /tmp/initial_store_count 2>/dev/null || echo "0")
CURRENT_LAYER_COUNT=$(get_layer_count)
CURRENT_STORE_COUNT=$(get_datastore_count)

# The task asks to create a store/layer in the 'cite' workspace
EXPECTED_WS="cite"

LAYER_FOUND="false"
LAYER_NAME=""
LAYER_TYPE=""
LAYER_SRS=""
LAYER_BBOX=""
LAYER_WORKSPACE=""
LAYER_IN_CITE="false"
STORE_FOUND="false"
STORE_NAME=""
STORE_TYPE=""

# Try to find ne_countries layer in cite workspace (exact match)
LAYER_STATUS=$(gs_rest_status "workspaces/${EXPECTED_WS}/layers/ne_countries.json")
if [ "$LAYER_STATUS" = "200" ]; then
    LAYER_DATA=$(gs_rest_get "workspaces/${EXPECTED_WS}/layers/ne_countries.json")
    LAYER_FOUND="true"
    LAYER_NAME="ne_countries"
    LAYER_WORKSPACE="cite"
    LAYER_IN_CITE="true"
fi

# Search layers in cite workspace for partial match
if [ "$LAYER_FOUND" = "false" ]; then
    CITE_LAYERS=$(gs_rest_get "workspaces/${EXPECTED_WS}/layers.json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ls = d.get('layers', {}).get('layer', [])
if not isinstance(ls, list):
    ls = [ls] if ls else []
for l in ls:
    print(l['name'])
" 2>/dev/null)

    for layer_name in $CITE_LAYERS; do
        layer_lower=$(echo "$layer_name" | tr '[:upper:]' '[:lower:]')
        if echo "$layer_lower" | grep -q "ne_countries\|countries\|admin_0"; then
            LAYER_FOUND="true"
            LAYER_NAME="$layer_name"
            LAYER_WORKSPACE="cite"
            LAYER_IN_CITE="true"
            LAYER_DATA=$(gs_rest_get "workspaces/${EXPECTED_WS}/layers/${layer_name}.json")
            break
        fi
    done
fi

# Fallback: check if agent published in a different workspace (only if layer count increased by 1-2)
if [ "$LAYER_FOUND" = "false" ] && [ "$CURRENT_LAYER_COUNT" -gt "$INITIAL_LAYER_COUNT" ] && [ "$((CURRENT_LAYER_COUNT - INITIAL_LAYER_COUNT))" -le 2 ]; then
    # Search all layers but exclude those in pre-existing 'ne' workspace postgis_ne store
    # Output format: workspace_name|layer_name
    ALL_LAYERS_WITH_WS=$(gs_rest_get "layers.json" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
ls = d.get('layers', {}).get('layer', [])
if not isinstance(ls, list):
    ls = [ls] if ls else []
for l in ls:
    name = l['name']
    href = l.get('href', '')
    # Skip ne workspace layers (pre-published by setup)
    if '/workspaces/ne/' not in href:
        # Extract workspace from href
        m = re.search(r'/workspaces/([^/]+)/', href)
        ws = m.group(1) if m else 'unknown'
        print(f'{ws}|{name}')
" 2>/dev/null)

    while IFS='|' read -r ws_name layer_name; do
        layer_lower=$(echo "$layer_name" | tr '[:upper:]' '[:lower:]')
        if echo "$layer_lower" | grep -q "ne_countries\|countries\|admin_0"; then
            LAYER_FOUND="true"
            LAYER_NAME="$layer_name"
            LAYER_WORKSPACE="$ws_name"
            LAYER_IN_CITE="false"
            if [ "$ws_name" = "cite" ]; then
                LAYER_IN_CITE="true"
            fi
            LAYER_DATA=$(gs_rest_get "layers/${layer_name}.json")
            break
        fi
    done <<< "$ALL_LAYERS_WITH_WS"
fi

# Get layer details if found
if [ "$LAYER_FOUND" = "true" ] && [ -n "$LAYER_NAME" ]; then
    LAYER_TYPE=$(echo "$LAYER_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('type',''))" 2>/dev/null || echo "")

    RESOURCE_HREF=$(echo "$LAYER_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('layer',{}).get('resource',{}).get('href',''))" 2>/dev/null || echo "")
    if [ -n "$RESOURCE_HREF" ]; then
        FT_DATA=$(curl -s -u "$GS_AUTH" -H "Accept: application/json" "$RESOURCE_HREF" 2>/dev/null)
        LAYER_SRS=$(echo "$FT_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); ft=d.get('featureType',{}); print(ft.get('srs',''))" 2>/dev/null || echo "")
        LAYER_BBOX=$(echo "$FT_DATA" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ft = d.get('featureType', {})
nb = ft.get('nativeBoundingBox', {})
print(f\"{nb.get('minx','')},{nb.get('miny','')},{nb.get('maxx','')},{nb.get('maxy','')}\")
" 2>/dev/null || echo "")
    fi
fi

# Check for PostGIS data store — only in cite workspace
CITE_STORES=$(gs_rest_get "workspaces/${EXPECTED_WS}/datastores.json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ds = d.get('dataStores', {}).get('dataStore', [])
if not isinstance(ds, list):
    ds = [ds] if ds else []
for s in ds:
    print(s['name'])
" 2>/dev/null)

for store_name in $CITE_STORES; do
    store_lower=$(echo "$store_name" | tr '[:upper:]' '[:lower:]')
    if echo "$store_lower" | grep -q "postgis\|natural_earth\|ne_\|countries"; then
        STORE_FOUND="true"
        STORE_NAME="$store_name"
        STORE_DATA=$(gs_rest_get "workspaces/${EXPECTED_WS}/datastores/${store_name}.json")
        STORE_TYPE=$(echo "$STORE_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dataStore',{}).get('type',''))" 2>/dev/null || echo "")
        break
    fi
done

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_layer_count": ${INITIAL_LAYER_COUNT},
    "current_layer_count": ${CURRENT_LAYER_COUNT},
    "initial_store_count": ${INITIAL_STORE_COUNT},
    "current_store_count": ${CURRENT_STORE_COUNT},
    "layer_found": ${LAYER_FOUND},
    "layer_name": "$(json_escape "$LAYER_NAME")",
    "layer_workspace": "$(json_escape "$LAYER_WORKSPACE")",
    "layer_in_cite": ${LAYER_IN_CITE},
    "layer_type": "$(json_escape "$LAYER_TYPE")",
    "layer_srs": "$(json_escape "$LAYER_SRS")",
    "layer_bbox": "$(json_escape "$LAYER_BBOX")",
    "store_found": ${STORE_FOUND},
    "store_name": "$(json_escape "$STORE_NAME")",
    "store_type": "$(json_escape "$STORE_TYPE")",
    "gui_interaction_detected": ${GUI_INTERACTION},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/publish_shapefile_layer_result.json"

echo "=== Export complete ==="
