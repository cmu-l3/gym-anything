#!/bin/bash
echo "=== Exporting export_bordering_countries results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected output path
OUTPUT_PATH="/home/ga/gvsig_data/exports/germany_neighbors.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/germany_neighbors.dbf"
OUTPUT_SHX="/home/ga/gvsig_data/exports/germany_neighbors.shx"

# Check if output files exist
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Check for sidecar files (required for valid shapefile)
SIDECARS_EXIST="false"
if [ -f "$OUTPUT_DBF" ] && [ -f "$OUTPUT_SHX" ]; then
    SIDECARS_EXIST="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_dbf_path": "$OUTPUT_DBF",
    "output_shx_path": "$OUTPUT_SHX",
    "output_size_bytes": $OUTPUT_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "sidecars_exist": $SIDECARS_EXIST,
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