#!/bin/bash
echo "=== Exporting supply_chain_hub_lines result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

take_screenshot /tmp/task_end.png

EXPORT_FILE="/home/ga/GIS_Data/exports/hub_connections.geojson"
WAREHOUSES_FILE="/home/ga/GIS_Data/logistics/warehouses.geojson"
STORES_FILE="/home/ga/GIS_Data/logistics/retail_stores.geojson"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Basic File Checks
FILE_EXISTS="false"
FILE_SIZE=0
FILE_NEW="false"

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_NEW="true"
    fi
fi

# 2. Advanced Geometric Analysis using Python (shapely/geopandas installed in env)
ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import math
import sys

try:
    # Load Files
    with open("/home/ga/GIS_Data/exports/hub_connections.geojson", 'r') as f:
        output_data = json.load(f)
    with open("/home/ga/GIS_Data/logistics/warehouses.geojson", 'r') as f:
        warehouses_data = json.load(f)
    with open("/home/ga/GIS_Data/logistics/retail_stores.geojson", 'r') as f:
        stores_data = json.load(f)

    # Basic Structure Check
    features = output_data.get('features', [])
    feature_count = len(features)
    
    all_linestrings = all(f['geometry']['type'] == 'LineString' for f in features)
    
    # Check Attribute Transfer (HubName)
    has_hub_attribute = False
    if features:
        props = features[0].get('properties', {})
        # QGIS Hub tool usually adds "HubName" or copies the attribute name specified (e.g., "name")
        # It usually adds "HubName" or "HubDist"
        keys = [k.lower() for k in props.keys()]
        if any('name' in k or 'hub' in k for k in keys):
            has_hub_attribute = True

    # Geometric Connectivity & Optimality Check
    # For every line, one end should be a store, the other a warehouse
    # And it should connect to the CLOSEST warehouse
    
    warehouses = []
    for f in warehouses_data['features']:
        c = f['geometry']['coordinates']
        warehouses.append({'name': f['properties']['name'], 'coords': c})

    stores = []
    for f in stores_data['features']:
        c = f['geometry']['coordinates']
        stores.append({'name': f['properties']['store_name'], 'coords': c})

    def dist_sq(p1, p2):
        return (p1[0]-p2[0])**2 + (p1[1]-p2[1])**2

    connected_correctly = 0
    optimal_connections = 0
    
    for feat in features:
        geom = feat['geometry']
        if geom['type'] != 'LineString': continue
        
        coords = geom['coordinates'] # [[x1,y1], [x2,y2]]
        p1 = coords[0]
        p2 = coords[-1]
        
        # Check endpoints against stores/warehouses (with tolerance)
        tolerance_sq = 0.000001 # approx 100m tolerance for coordinate matching
        
        matched_store = None
        matched_warehouse = None
        
        # Check P1
        for s in stores:
            if dist_sq(p1, s['coords']) < tolerance_sq: matched_store = s
        for w in warehouses:
            if dist_sq(p1, w['coords']) < tolerance_sq: matched_warehouse = w
            
        # Check P2
        for s in stores:
            if dist_sq(p2, s['coords']) < tolerance_sq: matched_store = s
        for w in warehouses:
            if dist_sq(p2, w['coords']) < tolerance_sq: matched_warehouse = w
            
        if matched_store and matched_warehouse:
            connected_correctly += 1
            
            # Check if this warehouse is actually the closest one to the store
            closest_w = None
            min_d = float('inf')
            for w in warehouses:
                d = dist_sq(matched_store['coords'], w['coords'])
                if d < min_d:
                    min_d = d
                    closest_w = w
            
            if closest_w['name'] == matched_warehouse['name']:
                optimal_connections += 1

    result = {
        "valid_geojson": True,
        "feature_count": feature_count,
        "all_linestrings": all_linestrings,
        "has_hub_attribute": has_hub_attribute,
        "valid_connections_count": connected_correctly,
        "optimal_connections_count": optimal_connections
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({
        "valid_geojson": False, 
        "error": str(e),
        "feature_count": 0,
        "all_linestrings": False,
        "valid_connections_count": 0,
        "optimal_connections_count": 0
    }))
PYEOF
)

# 3. Clean up
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 4. Save Result
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_new": $FILE_NEW,
    "file_size": $FILE_SIZE,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="