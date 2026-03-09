#!/bin/bash
echo "=== Exporting dissolve_countries_by_continent result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/GIS_Data/exports/continents_dissolved.geojson"

# 3. Analyze Output File
FILE_EXISTS="false"
FILE_SIZE=0
IS_VALID_GEOJSON="false"
FEATURE_COUNT=0
GEOMETRY_TYPE="unknown"
HAS_CONTINENT_FIELD="false"
FOUND_CONTINENTS="[]"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Python script to analyze GeoJSON content
    ANALYSIS=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/continents_dissolved.geojson", "r") as f:
        data = json.load(f)
    
    # Check basic structure
    if data.get("type") != "FeatureCollection":
        print("IS_VALID_GEOJSON=false")
        sys.exit(0)
        
    features = data.get("features", [])
    count = len(features)
    
    print(f"IS_VALID_GEOJSON=true")
    print(f"FEATURE_COUNT={count}")
    
    # Check Geometry Type (should be Polygon or MultiPolygon)
    geoms = set()
    for feat in features:
        g = feat.get("geometry")
        if g:
            geoms.add(g.get("type"))
    
    # Simplify geometry report
    if not geoms:
        print("GEOMETRY_TYPE=none")
    elif "MultiPolygon" in geoms or "Polygon" in geoms:
        print("GEOMETRY_TYPE=Polygon")
    else:
        print(f"GEOMETRY_TYPE={list(geoms)[0]}")

    # Check for Continent Field and Values
    has_field = False
    found_values = set()
    
    # Look for likely field names
    target_fields = ["CONTINENT", "continent", "Continent"]
    
    for feat in features:
        props = feat.get("properties", {})
        for key in props.keys():
            if key in target_fields:
                has_field = True
                val = props[key]
                if val:
                    found_values.add(str(val))
    
    print(f"HAS_CONTINENT_FIELD={'true' if has_field else 'false'}")
    
    # Print found values as JSON array
    import json
    print(f"FOUND_CONTINENTS={json.dumps(list(found_values))}")

except Exception as e:
    print(f"IS_VALID_GEOJSON=false")
PYEOF
)
    # Execute the python output variables in bash
    eval "$ANALYSIS"
fi

# 4. Check App State
APP_RUNNING=$(is_qgis_running && echo "true" || echo "false")

# 5. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "is_valid_geojson": $IS_VALID_GEOJSON,
    "feature_count": $FEATURE_COUNT,
    "geometry_type": "$GEOMETRY_TYPE",
    "has_continent_field": $HAS_CONTINENT_FIELD,
    "found_continents": $FOUND_CONTINENTS,
    "app_running": $APP_RUNNING
}
EOF

# 6. Save to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="