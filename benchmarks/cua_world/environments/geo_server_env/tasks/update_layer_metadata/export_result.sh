#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting update_layer_metadata result ==="

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Retrieve initial state for comparison
INITIAL_TITLE=$(cat /tmp/initial_layer_title.txt 2>/dev/null || echo "")
INITIAL_QUERYABLE=$(cat /tmp/initial_queryable.txt 2>/dev/null || echo "")

# Fetch current FeatureType state (Title, Abstract, Keywords, SRS)
FT_JSON=$(gs_rest_get "workspaces/ne/datastores/postgis_ne/featuretypes/ne_countries.json" 2>/dev/null)

# Fetch current Layer state (Queryable)
LAYER_JSON=$(gs_rest_get "layers/ne:ne_countries.json" 2>/dev/null)

# Extract values using Python
# We use Python for robust JSON parsing instead of fragile grep/sed
PYTHON_SCRIPT=$(cat <<EOF
import sys, json, os

def get_safe(json_str, path, default=None):
    try:
        data = json.loads(json_str)
        for key in path:
            data = data.get(key, {})
        if isinstance(data, dict) and not data:
            return default
        return data
    except Exception:
        return default

ft_json = """$FT_JSON"""
layer_json = """$LAYER_JSON"""

# Parse FeatureType
current_title = get_safe(ft_json, ['featureType', 'title'], '')
current_abstract = get_safe(ft_json, ['featureType', 'abstract'], '')
current_srs = get_safe(ft_json, ['featureType', 'srs'], '')

keywords_data = get_safe(ft_json, ['featureType', 'keywords', 'string'], [])
if isinstance(keywords_data, str):
    keywords = [keywords_data]
elif isinstance(keywords_data, list):
    keywords = keywords_data
else:
    keywords = []
keywords = [k.lower() for k in keywords]

# Parse Layer
queryable = get_safe(layer_json, ['layer', 'queryable'], False)

result = {
    "current_title": current_title,
    "current_abstract": current_abstract,
    "current_keywords": keywords,
    "current_srs": current_srs,
    "current_queryable": queryable
}
print(json.dumps(result))
EOF
)

PARSED_DATA=$(python3 -c "$PYTHON_SCRIPT")

# Check WMS GetCapabilities as a secondary verification
# This confirms the changes actually propagated to the service
WMS_CAPS=$(curl -s "http://localhost:8080/geoserver/ne/wms?service=WMS&version=1.1.1&request=GetCapabilities" 2>/dev/null || echo "")
WMS_TITLE_CHECK=$(echo "$WMS_CAPS" | grep -q "World Political Boundaries" && echo "true" || echo "false")
WMS_QUERYABLE_CHECK=$(echo "$WMS_CAPS" | grep -q 'queryable="1"' && echo "true" || echo "false")

# Check for GUI interaction via access logs
GUI_INTERACTION=$(check_gui_interaction)

# Construct final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_title": "$(json_escape "$INITIAL_TITLE")",
    "initial_queryable": "$(json_escape "$INITIAL_QUERYABLE")",
    "parsed_data": $PARSED_DATA,
    "wms_checks": {
        "title_propagated": $WMS_TITLE_CHECK,
        "queryable_propagated": $WMS_QUERYABLE_CHECK
    },
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "=== Export complete ==="
cat /tmp/task_result.json