#!/bin/bash
echo "=== Exporting identify_landlocked_parcels_buffer result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

take_screenshot /tmp/task_end.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/easement_buffers.geojson"

INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

# Verify output using Python
ANALYSIS_JSON='{}'
FILE_EXISTS="false"
FILE_SIZE=0

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys
try:
    from shapely.geometry import shape
    from shapely.ops import transform
    import pyproj
except ImportError:
    # If shapely is missing, simple check
    pass

try:
    with open("/home/ga/GIS_Data/exports/easement_buffers.geojson") as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print('{"valid": false, "error": "Not a FeatureCollection"}')
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)
    
    if feature_count == 0:
         print('{"valid": true, "feature_count": 0, "avg_area": 0, "geometry_type": "None"}')
         sys.exit(0)

    # Check Geometry Type
    geom_types = set([f["geometry"]["type"] for f in features if f.get("geometry")])
    is_polygon = all(t in ["Polygon", "MultiPolygon"] for t in geom_types)
    
    # Calculate Area
    # If data is in WGS84, we need to project to measure area in sq meters.
    # Assuming the agent exported in WGS84 as requested or kept UTM.
    # We will try to detect.
    
    # Simple heuristic: if coordinates are < 180, it's lat/lon.
    first_coord = features[0]["geometry"]["coordinates"][0][0]
    # Handle Polygon nesting
    if isinstance(first_coord[0], list): first_coord = first_coord[0]
    
    is_latlon = abs(first_coord[0]) <= 180
    
    avg_area = 0
    ids_found = []
    
    try:
        from pyproj import Transformer
        from shapely.geometry import shape
        from shapely.ops import transform
        
        project = None
        if is_latlon:
            # WGS84 to UTM 10N
            project = Transformer.from_crs("EPSG:4326", "EPSG:32610", always_xy=True).transform
        
        total_area = 0
        for f in features:
            geom = shape(f["geometry"])
            if project:
                geom = transform(project, geom)
            total_area += geom.area
            if "id" in f.get("properties", {}):
                ids_found.append(f["properties"]["id"])
            
        avg_area = total_area / feature_count
        
    except ImportError:
        avg_area = -1 # Cannot calculate
        
    result = {
        "valid": True,
        "feature_count": feature_count,
        "geometry_type": list(geom_types)[0] if geom_types else "None",
        "avg_area": avg_area,
        "ids_found": sorted(ids_found),
        "is_latlon": is_latlon
    }
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
else
    # Check for misnamed file
    ALT=$(find "$EXPORT_DIR" -name "*buffer*.geojson" -mmin -10 2>/dev/null | head -1)
    if [ -n "$ALT" ]; then
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c%s "$ALT" 2>/dev/null || echo "0")
        ANALYSIS_JSON='{"valid": true, "feature_count": -1, "note": "alternative filename found"}'
    fi
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/task_result.json << EOF
{
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_path": "$EXPECTED_FILE",
    "file_size_bytes": $FILE_SIZE,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="