#!/bin/bash
echo "=== Exporting refactor_attribute_schema result ==="

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

EXPORT_FILE="/home/ga/GIS_Data/exports/clean_stations.geojson"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check file status
FILE_EXISTS="false"
FILE_SIZE=0
IS_NEW="false"
ANALYSIS="{}"

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi

    # Python analysis of the GeoJSON structure and types
    ANALYSIS=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/clean_stations.geojson") as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print(json.dumps({"valid": False, "error": "Not a FeatureCollection"}))
        sys.exit(0)

    features = data.get("features", [])
    count = len(features)
    
    if count == 0:
        print(json.dumps({"valid": True, "count": 0}))
        sys.exit(0)

    # Check first feature for schema
    props = features[0].get("properties", {})
    keys = list(props.keys())
    
    # Check for specific fields
    has_station_id = "station_id" in keys
    has_name = "name" in keys
    has_temperature = "temperature" in keys
    has_date = "date" in keys
    
    # Check for forbidden fields
    forbidden = ["STN_ID_X", "LOC_NM", "READ_VAL", "LEGACY_CD", "TECH_N"]
    found_forbidden = [k for k in keys if k in forbidden]
    
    # Check data types
    temp_val = props.get("temperature")
    temp_is_numeric = isinstance(temp_val, (int, float))
    
    # Check data integrity (spot check)
    # Original STN001 had temp 12.5. Let's find STN001 in output
    integrity_check = False
    for f in features:
        p = f.get("properties", {})
        if p.get("station_id") == "STN001":
            # Allow float comparison with tolerance
            try:
                if abs(float(p.get("temperature", -999)) - 12.5) < 0.01:
                    integrity_check = True
            except:
                pass
            break

    result = {
        "valid": True,
        "count": count,
        "keys": keys,
        "has_station_id": has_station_id,
        "has_name": has_name,
        "has_temperature": has_temperature,
        "has_date": has_date,
        "found_forbidden": found_forbidden,
        "temp_is_numeric": temp_is_numeric,
        "integrity_check": integrity_check
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "is_new": $IS_NEW,
    "analysis": $ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="