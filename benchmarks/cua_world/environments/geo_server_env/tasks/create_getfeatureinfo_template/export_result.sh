#!/bin/bash
echo "=== Exporting create_getfeatureinfo_template result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

TEMPLATE_PATH="/opt/geoserver/data_dir/workspaces/ne/postgis_ne/ne_countries/content.ftl"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if file exists inside container
echo "Checking for template file..."
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if docker exec gs-app test -f "$TEMPLATE_PATH"; then
    FILE_EXISTS="true"
    # Read content (base64 to avoid JSON escaping issues with HTML/FTL tags)
    FILE_CONTENT=$(docker exec gs-app cat "$TEMPLATE_PATH" | base64 -w 0)
    FILE_SIZE=$(docker exec gs-app stat -c %s "$TEMPLATE_PATH")
    
    # Check modification time
    # getting epoch from inside container
    FILE_MTIME=$(docker exec gs-app stat -c %Y "$TEMPLATE_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Test the Live GetFeatureInfo response
echo "Testing live GetFeatureInfo..."
TEST_URL="http://localhost:8080/geoserver/ne/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetFeatureInfo&FORMAT=image/png&TRANSPARENT=true&QUERY_LAYERS=ne:ne_countries&LAYERS=ne:ne_countries&STYLES=&INFO_FORMAT=text/html&FEATURE_COUNT=1&X=50&Y=50&SRS=EPSG:4326&WIDTH=101&HEIGHT=101&BBOX=1.0,46.0,3.0,48.0"

LIVE_RESPONSE=$(curl -s "$TEST_URL")
# Save response for debugging/verification
echo "$LIVE_RESPONSE" > /tmp/live_response.html

# 3. Compare with baseline
BASELINE_RESPONSE=$(cat /tmp/baseline_response.txt 2>/dev/null || echo "")
RESPONSE_CHANGED="false"

# Simple string comparison (ignoring minor whitespace changes would be better in python, strict here)
if [ "$LIVE_RESPONSE" != "$BASELINE_RESPONSE" ] && [ -n "$LIVE_RESPONSE" ]; then
    RESPONSE_CHANGED="true"
fi

# 4. Check GUI interaction
GUI_INTERACTION=$(check_gui_interaction)

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_base64": "$FILE_CONTENT",
    "file_size": $FILE_SIZE,
    "response_changed": $RESPONSE_CHANGED,
    "live_response_base64": "$(echo "$LIVE_RESPONSE" | base64 -w 0)",
    "gui_interaction_detected": $GUI_INTERACTION,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_getfeatureinfo_template_result.json"

echo "=== Export complete ==="