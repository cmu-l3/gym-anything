#!/bin/bash
echo "=== Exporting Pole of Inaccessibility result ==="

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

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
EXPORT_DIR="/home/ga/GIS_Data/exports"
GEOJSON_FILE="$EXPORT_DIR/somalia_pole.geojson"
REPORT_FILE="$EXPORT_DIR/distance_report.txt"

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Analyze GeoJSON Output
GEOJSON_EXISTS="false"
GEOJSON_SIZE=0
GEOJSON_ANALYSIS="{}"

if [ -f "$GEOJSON_FILE" ]; then
    GEOJSON_EXISTS="true"
    GEOJSON_SIZE=$(stat -c%s "$GEOJSON_FILE" 2>/dev/null || echo "0")
    
    # Python analysis of the GeoJSON
    GEOJSON_ANALYSIS=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/somalia_pole.geojson") as f:
        data = json.load(f)
    
    features = data.get("features", [])
    feature_count = len(features)
    
    if feature_count > 0:
        feat = features[0]
        geom_type = feat.get("geometry", {}).get("type", "")
        coords = feat.get("geometry", {}).get("coordinates", [])
        props = feat.get("properties", {})
        
        # Look for distance attribute (tool usually adds 'dist_to_boundary' or 'distance')
        dist_attr = None
        for key in props:
            if "dist" in key.lower():
                dist_attr = props[key]
                break
        
        print(json.dumps({
            "valid": True,
            "feature_count": feature_count,
            "geometry_type": geom_type,
            "coordinates": coords,
            "distance_attribute": dist_attr,
            "properties_keys": list(props.keys())
        }))
    else:
        print(json.dumps({"valid": True, "feature_count": 0}))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Analyze Report Output
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_VALUE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(head -n 1 "$REPORT_FILE")
    # Extract number from report
    REPORT_VALUE=$(echo "$REPORT_CONTENT" | grep -oE "[0-9]+(\.[0-9]+)?" | head -1 || echo "0")
fi

# Check file timestamps
FILES_NEW="false"
if [ "$GEOJSON_EXISTS" = "true" ]; then
    FILE_TIME=$(stat -c %Y "$GEOJSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "geojson_exists": $GEOJSON_EXISTS,
    "geojson_size": $GEOJSON_SIZE,
    "geojson_analysis": $GEOJSON_ANALYSIS,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$(echo $REPORT_CONTENT | sed 's/"/\\"/g')",
    "report_value": "$REPORT_VALUE",
    "files_created_during_task": $FILES_NEW,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="