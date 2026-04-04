#!/bin/bash
echo "=== Exporting extract_country_boundaries results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_SHP="/home/ga/gvsig_data/exports/country_boundaries.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/country_boundaries.dbf"

# 1. Check file existence and timestamps
SHP_EXISTS="false"
SHP_CREATED_DURING_TASK="false"
SHP_SIZE="0"

if [ -f "$OUTPUT_SHP" ]; then
    SHP_EXISTS="true"
    SHP_SIZE=$(stat -c %s "$OUTPUT_SHP")
    SHP_MTIME=$(stat -c %Y "$OUTPUT_SHP")
    
    if [ "$SHP_MTIME" -gt "$TASK_START" ]; then
        SHP_CREATED_DURING_TASK="true"
    fi
fi

DBF_EXISTS="false"
if [ -f "$OUTPUT_DBF" ]; then
    DBF_EXISTS="true"
fi

# 2. Check if App is still running
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result for the verifier
# We only store metadata here; the verifier will pull the actual SHP/DBF files
# to analyze geometry type locally.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "shp_exists": $SHP_EXISTS,
    "dbf_exists": $DBF_EXISTS,
    "shp_created_during_task": $SHP_CREATED_DURING_TASK,
    "shp_size_bytes": $SHP_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "output_shp_path": "$OUTPUT_SHP",
    "output_dbf_path": "$OUTPUT_DBF"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result JSON:"
cat /tmp/task_result.json