#!/bin/bash
echo "=== Exporting generate_city_blocks_from_roads result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

take_screenshot /tmp/task_end.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/city_blocks.geojson"
INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
ANALYSIS_JSON="{}"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    # Python analysis of the output
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/city_blocks.geojson") as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print(json.dumps({"valid": False, "error": "Not a FeatureCollection"}))
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)

    # Geometry check
    all_polygons = all(f.get("geometry", {}).get("type") in ["Polygon", "MultiPolygon"] for f in features)
    
    # Field check
    has_area_field = False
    area_values = []
    
    if feature_count > 0:
        props = features[0].get("properties", {})
        # Case insensitive check for area_ha
        keys = [k.lower() for k in props.keys()]
        if "area_ha" in keys:
            has_area_field = True
            
            # Extract values
            real_key = next(k for k in props.keys() if k.lower() == "area_ha")
            for f in features:
                val = f.get("properties", {}).get(real_key)
                if val is not None:
                    try:
                        area_values.append(float(val))
                    except:
                        pass

    result = {
        "valid": True,
        "feature_count": feature_count,
        "all_polygons": all_polygons,
        "has_area_field": has_area_field,
        "area_values": area_values
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
else
    # Check for misnamed file
    ALT=$(find "$EXPORT_DIR" -name "*block*" -name "*.geojson" -mmin -10 2>/dev/null | head -1)
    if [ -n "$ALT" ]; then
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c%s "$ALT" 2>/dev/null || echo "0")
        ANALYSIS_JSON='{"valid": false, "note": "alternative filename found, manual check required"}'
    fi
fi

# Close QGIS
if pgrep -f "qgis" > /dev/null; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/task_result.json << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
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