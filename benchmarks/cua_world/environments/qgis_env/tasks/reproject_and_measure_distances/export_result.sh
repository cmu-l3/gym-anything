#!/bin/bash
echo "=== Exporting reproject_and_measure_distances result ==="

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
CSV_FILE="$EXPORT_DIR/road_measurements.csv"
GEOJSON_FILE="$EXPORT_DIR/roads_utm.geojson"

INITIAL_CSV=$(cat /tmp/initial_csv_count 2>/dev/null || echo "0")
INITIAL_GEOJSON=$(cat /tmp/initial_geojson_count 2>/dev/null || echo "0")
CURRENT_CSV=$(ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l || echo "0")
CURRENT_GEOJSON=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

# Analyze CSV output
CSV_EXISTS="false"
CSV_SIZE=0
CSV_ANALYSIS='{}'

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_FILE" 2>/dev/null || echo "0")

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/road_measurements.csv", newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        headers = reader.fieldnames or []

    row_count = len(rows)
    has_length_field = any("length" in h.lower() for h in headers)
    has_name_field = any("name" in h.lower() for h in headers)

    # Check if length values are numeric and positive
    lengths_valid = True
    length_values = []
    length_field = None
    for h in headers:
        if "length" in h.lower():
            length_field = h
            break

    if length_field:
        for row in rows:
            try:
                val = float(row[length_field])
                length_values.append(val)
                if val <= 0:
                    lengths_valid = False
            except (ValueError, TypeError):
                lengths_valid = False
    else:
        lengths_valid = False

    # Check road names
    road_names = []
    name_field = None
    for h in headers:
        if h.lower() == "name":
            name_field = h
            break
    if name_field:
        road_names = [row[name_field] for row in rows]

    has_road1 = any("Road 1" in n for n in road_names)
    has_road2 = any("Road 2" in n for n in road_names)

    result = {
        "valid": True,
        "row_count": row_count,
        "headers": headers,
        "has_length_field": has_length_field,
        "has_name_field": has_name_field,
        "lengths_valid": lengths_valid,
        "length_values": length_values,
        "has_road1": has_road1,
        "has_road2": has_road2
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"valid": False, "row_count": 0, "error": str(e)}))
PYEOF
    )
else
    # Check for alternative CSV
    ALT=$(find "$EXPORT_DIR" -name "*road*" -name "*.csv" -mmin -10 2>/dev/null | head -1)
    if [ -n "$ALT" ]; then
        CSV_EXISTS="true"
        CSV_SIZE=$(stat -c%s "$ALT" 2>/dev/null || echo "0")
        CSV_FILE="$ALT"
    fi
    CSV_ANALYSIS='{"valid": false, "row_count": 0}'
fi

# Analyze reprojected GeoJSON
GEOJSON_EXISTS="false"
GEOJSON_SIZE=0

if [ -f "$GEOJSON_FILE" ]; then
    GEOJSON_EXISTS="true"
    GEOJSON_SIZE=$(stat -c%s "$GEOJSON_FILE" 2>/dev/null || echo "0")
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/task_result.json << EOF
{
    "initial_csv_count": $INITIAL_CSV,
    "current_csv_count": $CURRENT_CSV,
    "initial_geojson_count": $INITIAL_GEOJSON,
    "current_geojson_count": $CURRENT_GEOJSON,
    "csv_exists": $CSV_EXISTS,
    "csv_path": "$CSV_FILE",
    "csv_size_bytes": $CSV_SIZE,
    "csv_analysis": $CSV_ANALYSIS,
    "geojson_exists": $GEOJSON_EXISTS,
    "geojson_path": "$GEOJSON_FILE",
    "geojson_size_bytes": $GEOJSON_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="
