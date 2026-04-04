#!/bin/bash
echo "=== Exporting Airport Proximity Modeler Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define Paths
MODEL_PATH="/home/ga/GIS_Data/models/airport_impact.model3"
OUTPUT_PATH="/home/ga/GIS_Data/exports/urban_noise_zones.geojson"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check Model File
MODEL_EXISTS="false"
MODEL_CREATED_DURING_TASK="false"
MODEL_SIZE=0

if [ -f "$MODEL_PATH" ]; then
    MODEL_EXISTS="true"
    MODEL_SIZE=$(stat -c%s "$MODEL_PATH")
    MODEL_MTIME=$(stat -c%Y "$MODEL_PATH")
    if [ "$MODEL_MTIME" -gt "$TASK_START" ]; then
        MODEL_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check Output GeoJSON
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0
FEATURE_COUNT=0
IS_VALID_GEOJSON="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi

    # Basic GeoJSON validation and feature counting using Python
    ANALYSIS=$(python3 << 'PYEOF'
import json
try:
    with open("/home/ga/GIS_Data/exports/urban_noise_zones.geojson", "r") as f:
        data = json.load(f)
    
    if data.get("type") == "FeatureCollection":
        print(f"IS_VALID_GEOJSON=true")
        print(f"FEATURE_COUNT={len(data.get('features', []))}")
    else:
        print(f"IS_VALID_GEOJSON=false")
        print(f"FEATURE_COUNT=0")
except Exception:
    print(f"IS_VALID_GEOJSON=false")
    print(f"FEATURE_COUNT=0")
PYEOF
)
    eval "$ANALYSIS"
fi

# 5. Check QGIS Status
APP_RUNNING="false"
if is_qgis_running; then
    APP_RUNNING="true"
fi

# 6. Prepare Results for Verification
# We copy the model and the output to temp for the verifier to read
if [ "$MODEL_EXISTS" = "true" ]; then
    cp "$MODEL_PATH" /tmp/submitted_model.model3
    chmod 666 /tmp/submitted_model.model3
fi

if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" /tmp/submitted_output.geojson
    chmod 666 /tmp/submitted_output.geojson
fi

# 7. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "model_exists": $MODEL_EXISTS,
    "model_created_during_task": $MODEL_CREATED_DURING_TASK,
    "model_size": $MODEL_SIZE,
    "output_exists": $OUTPUT_EXISTS,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "output_size": $OUTPUT_SIZE,
    "feature_count": $FEATURE_COUNT,
    "is_valid_geojson": $IS_VALID_GEOJSON,
    "app_running": $APP_RUNNING
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="