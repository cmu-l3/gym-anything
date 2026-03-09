#!/bin/bash
echo "=== Exporting create_wms_decoration_layout result ==="

source /workspace/scripts/task_utils.sh

# Record end time and screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_end_screenshot.png

# Paths
UNDECORATED_PATH="/home/ga/map_undecorated.png"
DECORATED_PATH="/home/ga/map_decorated.png"

# Check Undecorated Image
UNDEC_EXISTS="false"
UNDEC_SIZE="0"
UNDEC_MD5=""
if [ -f "$UNDECORATED_PATH" ]; then
    UNDEC_MTIME=$(stat -c %Y "$UNDECORATED_PATH" 2>/dev/null || echo "0")
    if [ "$UNDEC_MTIME" -gt "$TASK_START" ]; then
        UNDEC_EXISTS="true"
        UNDEC_SIZE=$(stat -c %s "$UNDECORATED_PATH" 2>/dev/null || echo "0")
        UNDEC_MD5=$(md5sum "$UNDECORATED_PATH" | cut -d' ' -f1)
    fi
fi

# Check Decorated Image
DEC_EXISTS="false"
DEC_SIZE="0"
DEC_MD5=""
if [ -f "$DECORATED_PATH" ]; then
    DEC_MTIME=$(stat -c %Y "$DECORATED_PATH" 2>/dev/null || echo "0")
    if [ "$DEC_MTIME" -gt "$TASK_START" ]; then
        DEC_EXISTS="true"
        DEC_SIZE=$(stat -c %s "$DECORATED_PATH" 2>/dev/null || echo "0")
        DEC_MD5=$(md5sum "$DECORATED_PATH" | cut -d' ' -f1)
    fi
fi

# Compare Images
IMAGES_DIFFER="false"
if [ "$UNDEC_EXISTS" = "true" ] && [ "$DEC_EXISTS" = "true" ]; then
    if [ "$UNDEC_MD5" != "$DEC_MD5" ]; then
        IMAGES_DIFFER="true"
    fi
fi

# Retrieve Layout XML from Container
LAYOUT_EXISTS="false"
LAYOUT_CONTENT=""
DATA_DIR=$(docker exec gs-app bash -c 'echo $GEOSERVER_DATA_DIR' 2>/dev/null)
[ -z "$DATA_DIR" ] && DATA_DIR="/opt/geoserver/data_dir"

# Check if file exists inside container
if docker exec gs-app test -f "$DATA_DIR/layouts/report_map.xml"; then
    LAYOUT_EXISTS="true"
    # Read content
    LAYOUT_CONTENT=$(docker exec gs-app cat "$DATA_DIR/layouts/report_map.xml")
fi

# Escape content for JSON
ESC_LAYOUT_CONTENT=$(json_escape "$LAYOUT_CONTENT")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "undecorated_exists": $UNDEC_EXISTS,
    "undecorated_size": $UNDEC_SIZE,
    "decorated_exists": $DEC_EXISTS,
    "decorated_size": $DEC_SIZE,
    "images_differ": $IMAGES_DIFFER,
    "layout_file_exists": $LAYOUT_EXISTS,
    "layout_content": "$ESC_LAYOUT_CONTENT",
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/create_wms_decoration_layout_result.json"

echo "=== Export complete ==="