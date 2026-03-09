#!/bin/bash
echo "=== Exporting extract_vertices_south_america results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Paths
OUTPUT_SHP="/home/ga/gvsig_data/exports/sa_vertices.shp"
OUTPUT_SHX="/home/ga/gvsig_data/exports/sa_vertices.shx"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if file exists
if [ -f "$OUTPUT_SHP" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    FILE_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "output_shp_path": "$OUTPUT_SHP",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Prepare files for extraction (copy .shp and .shx to /tmp for easy copy_from_env)
if [ "$OUTPUT_EXISTS" == "true" ]; then
    cp "$OUTPUT_SHP" /tmp/sa_vertices.shp
    cp "$OUTPUT_SHX" /tmp/sa_vertices.shx 2>/dev/null || true
    chmod 644 /tmp/sa_vertices.shp /tmp/sa_vertices.shx 2>/dev/null || true
fi

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="