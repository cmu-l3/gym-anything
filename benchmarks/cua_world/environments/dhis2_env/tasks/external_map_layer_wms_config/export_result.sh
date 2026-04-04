#!/bin/bash
# Export script for External Map Layer WMS Config task

echo "=== Exporting External Map Layer Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Querying for External Map Layer..."
# Query the external map layer
LAYER_JSON=$(dhis2_api "externalMapLayers?filter=name:eq:Global+Topography+WMS&fields=id,name,url,layers,mapService,imageFormat,created&paging=false" 2>/dev/null)

echo "Querying for Map..."
# Query the map and its views to check if the layer is used
# mapViews contains the configuration of layers in the map
MAP_JSON=$(dhis2_api "maps?filter=name:eq:Vegetation+Reference+Map&fields=id,name,created,mapViews[layer,externalMapLayer]&paging=false" 2>/dev/null)

# Process results with Python to create a clean JSON
python3 << PYEOF > /tmp/task_result.json
import json
import sys
from datetime import datetime

def parse_dhis2_date(s):
    if not s: return None
    s = s.replace('Z', '+00:00')
    return s 

try:
    layer_resp = json.loads('''$LAYER_JSON''')
    map_resp = json.loads('''$MAP_JSON''')
    task_start_iso = '$TASK_START_ISO'
    
    # Analyze Layer
    layers_list = layer_resp.get('externalMapLayers', [])
    layer_found = False
    layer_details = {}
    
    if layers_list:
        l = layers_list[0]
        layer_found = True
        layer_details = {
            'id': l.get('id'),
            'name': l.get('name'),
            'url': l.get('url'),
            'layers': l.get('layers'),
            'service': l.get('mapService'),
            'format': l.get('imageFormat'),
            'created': l.get('created')
        }

    # Analyze Map
    maps_list = map_resp.get('maps', [])
    map_found = False
    map_details = {}
    layer_used_in_map = False
    
    if maps_list:
        m = maps_list[0]
        map_found = True
        
        # Check if external layer is used in any view
        views = m.get('mapViews', [])
        for v in views:
            # Check if externalMapLayer object is present and matches ID
            ext_layer_obj = v.get('externalMapLayer', {})
            if ext_layer_obj and ext_layer_obj.get('id') == layer_details.get('id'):
                layer_used_in_map = True
                break
                
        map_details = {
            'id': m.get('id'),
            'name': m.get('name'),
            'created': m.get('created'),
            'layer_used': layer_used_in_map
        }

    result = {
        'task_start_iso': task_start_iso,
        'layer_found': layer_found,
        'layer_details': layer_details,
        'map_found': map_found,
        'map_details': map_details,
        'timestamp': datetime.now().isoformat()
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({'error': str(e)}))
PYEOF

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="