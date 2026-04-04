#!/bin/bash
echo "=== Exporting buffer_analysis_and_export result ==="

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
EXPECTED_FILE="$EXPORT_DIR/point_buffers.geojson"

INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

# Analyze the output file
FILE_EXISTS="false"
FILE_SIZE=0
FILE_VALID="false"
FEATURE_COUNT=0
ALL_POLYGONS="false"
HAS_VALID_GEOMETRIES="false"

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    # Validate GeoJSON and extract details using Python
    ANALYSIS=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/point_buffers.geojson") as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print("valid=false")
        print("feature_count=0")
        print("all_polygons=false")
        print("has_valid_geometries=false")
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)
    all_poly = True
    valid_geoms = True

    for feat in features:
        geom = feat.get("geometry", {})
        gtype = geom.get("type", "")
        if gtype not in ("Polygon", "MultiPolygon"):
            all_poly = False
        coords = geom.get("coordinates", [])
        if not coords or len(coords) == 0:
            valid_geoms = False

    print(f"valid=true")
    print(f"feature_count={feature_count}")
    print(f"all_polygons={'true' if all_poly else 'false'}")
    print(f"has_valid_geometries={'true' if valid_geoms else 'false'}")
except Exception as e:
    print("valid=false")
    print("feature_count=0")
    print("all_polygons=false")
    print("has_valid_geometries=false")
PYEOF
    )

    # Parse Python output
    eval "$ANALYSIS"
    FILE_VALID="${valid:-false}"
    FEATURE_COUNT="${feature_count:-0}"
    ALL_POLYGONS="${all_polygons:-false}"
    HAS_VALID_GEOMETRIES="${has_valid_geometries:-false}"
else
    # Check if saved with different name
    ALT_FILE=$(find "$EXPORT_DIR" -name "*buffer*" -name "*.geojson" -mmin -10 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c%s "$ALT_FILE" 2>/dev/null || echo "0")
        EXPECTED_FILE="$ALT_FILE"
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
    "file_valid_geojson": $FILE_VALID,
    "feature_count": $FEATURE_COUNT,
    "all_polygons": $ALL_POLYGONS,
    "has_valid_geometries": $HAS_VALID_GEOMETRIES,
    "expected_feature_count": 3,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="
