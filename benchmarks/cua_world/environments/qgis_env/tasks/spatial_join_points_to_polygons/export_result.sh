#!/bin/bash
echo "=== Exporting spatial_join_points_to_polygons result ==="

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
EXPECTED_FILE="$EXPORT_DIR/points_with_polygon_info.geojson"

INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

# Analyze the output file with Python
FILE_EXISTS="false"
FILE_SIZE=0
ANALYSIS_JSON='{}'

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/points_with_polygon_info.geojson") as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print('{"valid": false, "feature_count": 0, "has_join_fields": false, "all_points": false, "join_correct": false}')
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)

    # Check if features are points
    all_points = all(
        f.get("geometry", {}).get("type", "") == "Point"
        for f in features
    )

    # Check if join fields exist (from polygon layer)
    has_area_sqkm = False
    has_polygon_name = False
    join_correct = True

    # Expected mapping
    expected_mapping = {
        "Point A": "Area A",
        "Point B": "Area A",
        "Point C": "Area B"
    }

    for feat in features:
        props = feat.get("properties", {})
        all_keys = [str(k).lower() for k in props.keys()]

        # Check for area_sqkm field (may have prefix from join)
        if any("area_sqkm" in k for k in all_keys):
            has_area_sqkm = True

        # Check for polygon name field (joined)
        # The join may create name_2 or similar to avoid collision with point name
        prop_values = [str(v) for v in props.values()]
        if any(v in ("Area A", "Area B") for v in prop_values):
            has_polygon_name = True

        # Check join correctness
        point_name = props.get("name", "")
        if point_name in expected_mapping:
            expected_area = expected_mapping[point_name]
            found_match = any(str(v) == expected_area for v in props.values())
            if not found_match:
                join_correct = False

    result = {
        "valid": True,
        "feature_count": feature_count,
        "has_join_fields": has_area_sqkm or has_polygon_name,
        "has_area_sqkm": has_area_sqkm,
        "has_polygon_name": has_polygon_name,
        "all_points": all_points,
        "join_correct": join_correct
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"valid": False, "feature_count": 0, "has_join_fields": False, "all_points": False, "join_correct": False, "error": str(e)}))
PYEOF
    )
else
    # Check for alternative file names
    ALT=$(find "$EXPORT_DIR" -name "*join*" -o -name "*point*polygon*" -o -name "*spatial*" 2>/dev/null | grep -i geojson | head -1)
    if [ -n "$ALT" ]; then
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c%s "$ALT" 2>/dev/null || echo "0")
        EXPECTED_FILE="$ALT"
        ANALYSIS_JSON='{"valid": true, "feature_count": -1, "has_join_fields": false, "all_points": false, "join_correct": false, "note": "alternative filename"}'
    else
        ANALYSIS_JSON='{"valid": false, "feature_count": 0, "has_join_fields": false, "all_points": false, "join_correct": false}'
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
