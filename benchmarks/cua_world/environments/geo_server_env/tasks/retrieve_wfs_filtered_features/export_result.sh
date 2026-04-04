#!/bin/bash
echo "=== Exporting retrieve_wfs_filtered_features results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
GROUND_TRUTH_COUNT=$(cat /tmp/ground_truth_count.txt 2>/dev/null || echo "0")

GEOJSON_PATH="/home/ga/Documents/europe_countries.geojson"
REPORT_PATH="/home/ga/Documents/europe_report.txt"

# 1. Check GeoJSON file
GEOJSON_EXISTS="false"
GEOJSON_SIZE="0"
GEOJSON_MTIME="0"
GEOJSON_CREATED_DURING_TASK="false"
GEOJSON_VALID="false"
GEOJSON_FEATURE_COUNT="0"

if [ -f "$GEOJSON_PATH" ]; then
    GEOJSON_EXISTS="true"
    GEOJSON_SIZE=$(stat -c %s "$GEOJSON_PATH")
    GEOJSON_MTIME=$(stat -c %Y "$GEOJSON_PATH")
    
    if [ "$GEOJSON_MTIME" -gt "$TASK_START" ]; then
        GEOJSON_CREATED_DURING_TASK="true"
    fi

    # Basic JSON validity check and feature count using python
    # We do a more robust check in the verifier, but this gives us quick stats
    STATS=$(python3 -c "
import json, sys
try:
    with open('$GEOJSON_PATH') as f:
        data = json.load(f)
    if data.get('type') == 'FeatureCollection' and isinstance(data.get('features'), list):
        print(f'true|{len(data[\"features\"])}')
    else:
        print('false|0')
except:
    print('false|0')
" 2>/dev/null)
    
    GEOJSON_VALID=$(echo "$STATS" | cut -d'|' -f1)
    GEOJSON_FEATURE_COUNT=$(echo "$STATS" | cut -d'|' -f2)
fi

# 2. Check Report file
REPORT_EXISTS="false"
REPORT_MTIME="0"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read first few lines for debug/context
    REPORT_CONTENT=$(head -n 20 "$REPORT_PATH" | base64 -w 0)
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare files for export (copy to /tmp with known names)
cp "$GEOJSON_PATH" /tmp/exported_geojson.json 2>/dev/null || true
cp "$REPORT_PATH" /tmp/exported_report.txt 2>/dev/null || true
chmod 644 /tmp/exported_geojson.json /tmp/exported_report.txt 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "ground_truth_count": $GROUND_TRUTH_COUNT,
    "geojson": {
        "exists": $GEOJSON_EXISTS,
        "created_during_task": $GEOJSON_CREATED_DURING_TASK,
        "valid_structure": $GEOJSON_VALID,
        "feature_count": $GEOJSON_FEATURE_COUNT,
        "size_bytes": $GEOJSON_SIZE
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "content_base64": "$REPORT_CONTENT"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/task_result.json"

echo "=== Export complete ==="