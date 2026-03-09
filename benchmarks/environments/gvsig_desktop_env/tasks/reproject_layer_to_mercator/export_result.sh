#!/bin/bash
echo "=== Exporting reproject_layer_to_mercator result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Define Output Paths
OUTPUT_BASE="/home/ga/gvsig_data/exports/countries_mercator"
OUTPUT_SHP="${OUTPUT_BASE}.shp"
OUTPUT_SHX="${OUTPUT_BASE}.shx"
OUTPUT_DBF="${OUTPUT_BASE}.dbf"
OUTPUT_PRJ="${OUTPUT_BASE}.prj"

# 3. Check for Output Files
check_file() {
    if [ -f "$1" ]; then
        echo "true"
    else
        echo "false"
    fi
}

SHP_EXISTS=$(check_file "$OUTPUT_SHP")
SHX_EXISTS=$(check_file "$OUTPUT_SHX")
DBF_EXISTS=$(check_file "$OUTPUT_DBF")
PRJ_EXISTS=$(check_file "$OUTPUT_PRJ")

# 4. Check File Timestamp (Anti-Gaming)
FILE_CREATED_DURING_TASK="false"
if [ "$SHP_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    FILE_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
else
    FILE_SIZE="0"
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$(check_file "/tmp/task_final.png")

# 6. Prepare Files for Verification (Copy to /tmp for copy_from_env)
# We need to analyze the SHP and PRJ content in the verifier
if [ "$SHP_EXISTS" = "true" ]; then
    cp "$OUTPUT_SHP" /tmp/result_output.shp
    cp "$OUTPUT_SHX" /tmp/result_output.shx
    cp "$OUTPUT_DBF" /tmp/result_output.dbf
    cp "$OUTPUT_PRJ" /tmp/result_output.prj
    chmod 644 /tmp/result_output.*
fi

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "shp_exists": $SHP_EXISTS,
    "shx_exists": $SHX_EXISTS,
    "dbf_exists": $DBF_EXISTS,
    "prj_exists": $PRJ_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="