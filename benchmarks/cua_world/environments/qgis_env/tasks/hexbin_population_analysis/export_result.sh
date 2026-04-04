#!/bin/bash
echo "=== Exporting hexbin_population_analysis result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

take_screenshot /tmp/task_end.png

EXPORT_FILE="/home/ga/GIS_Data/exports/europe_hexbin_population.geojson"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Default values
FILE_EXISTS="false"
FILE_SIZE=0
IS_NEW="false"
ANALYSIS='{}'

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi

    # Python analysis of GeoJSON
    ANALYSIS=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/europe_hexbin_population.geojson") as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print(json.dumps({"valid": False, "error": "Not a FeatureCollection"}))
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)
    
    if feature_count == 0:
        print(json.dumps({"valid": True, "feature_count": 0}))
        sys.exit(0)

    # Check Geometry Type (Hexagons are Polygons)
    all_polygons = all(f.get("geometry", {}).get("type") in ["Polygon", "MultiPolygon"] for f in features)
    
    # Check Vertices count for Hexagon shape
    # A hexagon closed polygon usually has 7 points (6 vertices + 1 closing)
    # We check if features have roughly 6-8 vertices to confirm hex grid usage
    hex_shape_count = 0
    valid_centroids = 0
    total_pop_sum = 0
    
    has_count_field = False
    has_pop_field = False
    
    # Heuristics for field names
    count_keywords = ["count", "num", "cnt", "points"]
    pop_keywords = ["pop", "sum", "total"]

    # Check first feature for schema
    first_props = features[0].get("properties", {})
    keys = [k.lower() for k in first_props.keys()]
    
    has_count_field = any(any(k in key for k in count_keywords) for key in keys)
    has_pop_field = any(any(k in key for k in pop_keywords) for key in keys)
    
    for f in features:
        # Geometry check
        geom = f.get("geometry", {})
        coords = geom.get("coordinates", [])
        if coords and len(coords) > 0:
            # Simple polygon
            ring = coords[0]
            # Verify rough hexagon shape (approx 7 points)
            if 5 <= len(ring) <= 9:
                hex_shape_count += 1
            
            # Check centroid in Europe roughly
            # W=-15, S=35, E=45, N=72
            lons = [p[0] for p in ring]
            lats = [p[1] for p in ring]
            avg_lon = sum(lons) / len(lons)
            avg_lat = sum(lats) / len(lats)
            
            if -16 <= avg_lon <= 46 and 34 <= avg_lat <= 73:
                valid_centroids += 1

        # Attribute check
        props = f.get("properties", {})
        
        # Try to find population value
        # Look for the sum field specifically
        for k, v in props.items():
            if any(pk in k.lower() for pk in pop_keywords) and isinstance(v, (int, float)):
                total_pop_sum += v
                break

    result = {
        "valid": True,
        "feature_count": feature_count,
        "all_polygons": all_polygons,
        "hex_shape_ratio": hex_shape_count / feature_count,
        "europe_centroid_ratio": valid_centroids / feature_count,
        "has_count_field": has_count_field,
        "has_pop_field": has_pop_field,
        "total_population_sum": total_pop_sum
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Close QGIS cleanly
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$EXPORT_FILE",
    "file_size_bytes": $FILE_SIZE,
    "is_new_file": $IS_NEW,
    "analysis": $ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="