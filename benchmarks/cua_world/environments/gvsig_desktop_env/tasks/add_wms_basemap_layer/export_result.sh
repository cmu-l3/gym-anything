#!/bin/bash
echo "=== Exporting add_wms_basemap_layer results ==="

source /workspace/scripts/task_utils.sh

# -------------------------------------------------------------------
# 1. Capture Final State Evidence
# -------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# -------------------------------------------------------------------
# 2. Check Project File (Persistence Verification)
# -------------------------------------------------------------------
PROJECT_FILE="/home/ga/gvsig_data/projects/wms_basemap_project.gvsproj"

FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
WMS_URL_FOUND="false"
OSM_LAYER_FOUND="false"
LAYER_COUNT_ESTIMATE=0

if [ -f "$PROJECT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PROJECT_FILE")
    FILE_MTIME=$(stat -c %Y "$PROJECT_FILE")
    
    # Check timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Inspect file content
    # gvSIG projects can be text XML or Zip. We use grep -a (treat as text) to be safe.
    # Searching for the Mundial URL
    if grep -a -i "mundialis" "$PROJECT_FILE" > /dev/null; then
        WMS_URL_FOUND="true"
    fi
    
    # Searching for OSM layer name
    if grep -a -i "OSM" "$PROJECT_FILE" > /dev/null; then
        OSM_LAYER_FOUND="true"
    fi

    # Estimate layer count by counting "layer" tags or similar definitions
    # This is a rough heuristic
    LAYER_COUNT_ESTIMATE=$(grep -a -i -c "FLayer" "$PROJECT_FILE" || echo "0")
fi

# -------------------------------------------------------------------
# 3. Check Application State
# -------------------------------------------------------------------
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# -------------------------------------------------------------------
# 4. Export to JSON
# -------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_file_exists": $FILE_EXISTS,
    "project_file_path": "$PROJECT_FILE",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "wms_url_found": $WMS_URL_FOUND,
    "osm_layer_found": $OSM_LAYER_FOUND,
    "layer_count_estimate": $LAYER_COUNT_ESTIMATE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with broad permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON contents:"
cat /tmp/task_result.json
echo "=== Export complete ==="