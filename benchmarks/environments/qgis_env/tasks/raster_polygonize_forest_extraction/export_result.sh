#!/bin/bash
echo "=== Exporting raster_polygonize_forest_extraction result ==="

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

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/forest_zones.geojson"

INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
ANALYSIS_JSON='{}'

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    # Analyze output with Python
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/forest_zones.geojson") as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print(json.dumps({"valid": False, "error": "Not a FeatureCollection"}))
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)
    
    # Check geometry types
    all_polygons = all(f.get("geometry", {}).get("type") in ("Polygon", "MultiPolygon") for f in features)

    # Check attributes (filtering)
    # The polygonize tool typically creates a field 'DN' (Digital Number) or similar with the pixel value
    # We expect ONLY value 1 (Forest)
    
    correct_class_only = True
    found_classes = set()
    
    for f in features:
        props = f.get("properties", {})
        # Find the value field - usually DN, band, or value
        val = None
        for key, v in props.items():
            if key.upper() in ["DN", "VALUE", "BAND", "QGIS_VAR"]:
                try:
                    val = int(v)
                    break
                except:
                    pass
        
        # If no obvious field, check any integer field that is 1, 2, or 3
        if val is None:
            for v in props.values():
                if isinstance(v, int) or (isinstance(v, str) and v.isdigit()):
                    v_int = int(v)
                    if v_int in [1, 2, 3]:
                        val = v_int
                        break
        
        if val is not None:
            found_classes.add(val)
            if val != 1:
                correct_class_only = False
    
    result = {
        "valid": True,
        "feature_count": feature_count,
        "all_polygons": all_polygons,
        "correct_class_only": correct_class_only,
        "found_classes": list(found_classes)
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
else
    # Check for alternative file names
    ALT=$(find "$EXPORT_DIR" -name "*forest*" -name "*.geojson" -mmin -10 2>/dev/null | head -1)
    if [ -n "$ALT" ]; then
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c%s "$ALT" 2>/dev/null || echo "0")
        EXPECTED_FILE="$ALT"
        ANALYSIS_JSON='{"valid": false, "note": "Analysis skipped for alternative file - format unknown"}'
        
        # Attempt minimal analysis on alt file
        ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(json.dumps({"valid": True, "feature_count": len(data.get("features", []))}))
except:
    print(json.dumps({"valid": False}))
PYEOF
        "$ALT")
    else
        ANALYSIS_JSON='{"valid": false}'
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