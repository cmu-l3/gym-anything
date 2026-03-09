#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

GS_URL="http://localhost:8080/geoserver"
GS_AUTH="admin:Admin123!"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Feature Type Configuration (REST API)
# This contains the dimension configuration
FT_JSON=$(curl -s -u "$GS_AUTH" "${GS_URL}/rest/workspaces/seismic/datastores/postgis_seismic/featuretypes/earthquakes.json")

# 3. Get WMS Capabilities
# This confirms the layer is advertising time support to clients
GETCAPS_XML=$(curl -s "${GS_URL}/seismic/wms?service=WMS&version=1.1.1&request=GetCapabilities")

# 4. Test WMS GetMap with TIME parameter
# This confirms the configuration actually works to filter data
# Requesting a range that includes our data (Jan 2024)
TEST_URL="${GS_URL}/seismic/wms?service=WMS&version=1.1.1&request=GetMap&layers=seismic:earthquakes&styles=&bbox=-180,-90,180,90&width=800&height=400&srs=EPSG:4326&format=image/png&TIME=2024-01-01T00:00:00Z/2024-03-31T23:59:59Z"

GETMAP_HTTP_CODE=$(curl -s -o /tmp/wms_test.png -w "%{http_code}" "$TEST_URL")
GETMAP_SIZE=$(stat -c%s /tmp/wms_test.png 2>/dev/null || echo "0")
GETMAP_TYPE=$(file -b --mime-type /tmp/wms_test.png 2>/dev/null || echo "unknown")

# 5. Check Anti-Gaming Initial State
INITIAL_STATE=$(cat /tmp/initial_time_dimension_state.txt 2>/dev/null || echo "UNKNOWN")

# 6. Check for GUI Interaction
GUI_INTERACTION=$(check_gui_interaction)

# 7. Construct Result JSON
# We use python to construct valid JSON to avoid shell escaping issues
python3 -c "
import json, os, sys

# Load raw inputs
try:
    ft_json = json.loads('''$FT_JSON''')
except:
    ft_json = {}

result = {
    'feature_type': ft_json,
    'get_capabilities_has_time': 'Dimension name=\"time\"' in '''$GETCAPS_XML''' or '<Dimension name=\"time\"' in '''$GETCAPS_XML''',
    'get_map': {
        'http_code': '$GETMAP_HTTP_CODE',
        'size_bytes': int('$GETMAP_SIZE'),
        'mime_type': '$GETMAP_TYPE'
    },
    'initial_state': '$INITIAL_STATE',
    'gui_interaction': '$GUI_INTERACTION' == 'true',
    'result_nonce': '$(get_result_nonce)',
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"