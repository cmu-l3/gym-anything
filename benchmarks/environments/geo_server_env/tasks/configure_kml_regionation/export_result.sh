#!/bin/bash
echo "=== Exporting configure_kml_regionation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ==============================================================================
# 1. Query GeoServer REST API for Layer Configuration
# ==============================================================================
echo "Fetching final layer configuration..."
LAYER_JSON=$(gs_rest_get "workspaces/ne/layers/ne_populated_places.json")

# Extract KML settings using python for robust JSON parsing
# The metadata is a list of entries: [{"@key": "kml.regionateStrategy", "$": "val"}, ...]
PARSED_SETTINGS=$(echo "$LAYER_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    metadata = data.get('layer', {}).get('metadata', {}).get('entry', [])
    if not isinstance(metadata, list):
        metadata = [metadata]
    
    settings = {}
    for entry in metadata:
        key = entry.get('@key')
        val = entry.get('$')
        if key:
            settings[key] = val
            
    print(json.dumps({
        'enabled': data.get('layer', {}).get('enabled', False),
        'strategy': settings.get('kml.regionateStrategy', ''),
        'attribute': settings.get('kml.regionateAttribute', '') or settings.get('kml.regionateAttr', '')
    }))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)

echo "Parsed settings: $PARSED_SETTINGS"

# ==============================================================================
# 2. Check for GUI Interaction
# ==============================================================================
GUI_INTERACTION=$(check_gui_interaction)

# ==============================================================================
# 3. Create Result JSON
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "layer_config": $PARSED_SETTINGS,
    "gui_interaction_detected": $GUI_INTERACTION,
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)",
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "task_end": $(date +%s)
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/configure_kml_regionation_result.json"

echo "=== Export complete ==="