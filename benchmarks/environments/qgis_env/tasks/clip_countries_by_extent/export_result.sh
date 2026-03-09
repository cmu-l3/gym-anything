#!/bin/bash
echo "=== Exporting clip_countries_by_extent result ==="

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

# 1. Take Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Define Paths
OUTPUT_FILE="/home/ga/GIS_Data/exports/european_countries.geojson"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Analyze Result File
FILE_EXISTS="false"
FILE_SIZE=0
ANALYSIS_JSON='{}'

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_NEW="true"
    else
        FILE_NEW="false"
    fi

    # Python script to analyze the GeoJSON content
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/european_countries.geojson", 'r') as f:
        data = json.load(f)

    if data.get("type") != "FeatureCollection":
        print(json.dumps({"valid_geojson": False, "error": "Not a FeatureCollection"}))
        sys.exit(0)

    features = data.get("features", [])
    feature_count = len(features)
    
    # Geometry Check
    all_polygons = True
    bounds = {"xmin": 180, "xmax": -180, "ymin": 90, "ymax": -90}
    
    for feat in features:
        geom = feat.get("geometry", {})
        if not geom or geom.get("type") not in ["Polygon", "MultiPolygon"]:
            all_polygons = False
        
        # Approximate centroid check for bounds (simple bounding box expansion)
        # This is a rough check; rigorous check would parse all coords
        # Here we just want to see if we have features wildly outside
        pass 

    # Content Check (Countries)
    # Check common name fields
    found_names = []
    for feat in features:
        props = feat.get("properties", {})
        # Try finding a name field
        name = props.get("NAME") or props.get("ADMIN") or props.get("NAME_LONG") or props.get("sovereignt") or "Unknown"
        if name != "Unknown":
            found_names.append(name)
    
    # Check specific targets
    european_targets = ["France", "Germany", "Italy", "Spain", "Poland", "United Kingdom", "Ukraine", "Sweden", "Norway"]
    forbidden_targets = ["Brazil", "Australia", "India", "South Africa", "Japan", "United States", "Canada", "China"]
    
    found_europe = [c for c in european_targets if any(c.lower() in n.lower() for n in found_names)]
    found_forbidden = [c for c in forbidden_targets if any(c.lower() in n.lower() for n in found_names)]

    # Bounding Box Check (of the features' extent)
    # We rely on the fact that if forbidden countries are absent and feature count is low, clip likely worked
    
    result = {
        "valid_geojson": True,
        "feature_count": feature_count,
        "all_polygons": all_polygons,
        "found_names": found_names,
        "found_europe_count": len(found_europe),
        "found_forbidden_count": len(found_forbidden),
        "found_europe_list": found_europe,
        "found_forbidden_list": found_forbidden
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"valid_geojson": False, "error": str(e)}))
PYEOF
    )
else
    # Check if they saved it with a slightly different name
    ALT_FILE=$(find /home/ga/GIS_Data/exports -name "*.geojson" -mmin -10 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        FILE_EXISTS="true_alt"
        FILE_PATH_ACTUAL="$ALT_FILE"
        ANALYSIS_JSON='{"valid_geojson": false, "error": "Wrong filename"}' 
        # We enforce strict filename in this task for simplicity, or we could parse the alt file.
        # Let's enforce strict filename to teach attention to detail.
    else
        FILE_NEW="false"
        ANALYSIS_JSON='{"valid_geojson": false, "error": "File not found"}'
    fi
fi

# 4. Cleanup
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 5. Save Result
cat > /tmp/task_result.json << EOF
{
    "file_exists": "$FILE_EXISTS",
    "file_new": "$FILE_NEW",
    "file_size": $FILE_SIZE,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="