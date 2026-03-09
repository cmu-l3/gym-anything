#!/bin/bash
echo "=== Exporting export_multi_format_wfs results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EXPORT_DIR="/home/ga/exports"

# Function to get file info
get_file_info() {
    local filename="$1"
    local filepath="$EXPORT_DIR/$filename"
    
    if [ -f "$filepath" ]; then
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local created_during_task="false"
        
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during_task="true"
        fi
        
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Collect info for all expected files
GEOJSON_INFO=$(get_file_info "south_america.geojson")
KML_INFO=$(get_file_info "south_america.kml")
GML_INFO=$(get_file_info "south_america.gml")
CSV_INFO=$(get_file_info "south_america.csv")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "geojson": $GEOJSON_INFO,
        "kml": $KML_INFO,
        "gml": $GML_INFO,
        "csv": $CSV_INFO
    },
    "export_dir": "$EXPORT_DIR",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="