#!/bin/bash
echo "=== Exporting flood_risk_assessment results ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

# 1. Capture Final State
take_screenshot /tmp/task_end.png

OUTPUT_FILE="/home/ga/GIS_Data/exports/at_risk_towns.geojson"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 2. Analyze Output File
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
FEATURE_COUNT=0
TOWN_NAMES="[]"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Parse GeoJSON to extract town names for validation
    # This allows us to check content without needing complex geo-libraries in bash
    ANALYSIS=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/GIS_Data/exports/at_risk_towns.geojson", "r") as f:
        data = json.load(f)
    
    features = data.get("features", [])
    count = len(features)
    
    names = []
    for feat in features:
        props = feat.get("properties", {})
        # OSM places usually have a 'name' field
        name = props.get("name", props.get("NAME", "unknown"))
        if name:
            names.append(name)
            
    print(f"feature_count={count}")
    print(f"town_names={json.dumps(names)}")
    print("valid_json=true")
except Exception as e:
    print("feature_count=0")
    print("town_names=[]")
    print("valid_json=false")
PYEOF
    )
    
    # Execute the python output to set variables
    eval "$ANALYSIS"
fi

# 3. Create Result JSON
# Use temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "valid_json": ${valid_json:-false},
    "feature_count": ${FEATURE_COUNT:-0},
    "town_names": ${TOWN_NAMES:-[]},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"

# 4. Cleanup
if is_qgis_running; then
    # Graceful close attempt
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    pkill -u ga -f qgis 2>/dev/null || true
fi

echo "=== Export Complete ==="