#!/bin/bash
echo "=== Exporting validate_volume_conservation result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PROJECT_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
OUTPUT_JSON="$RESULTS_DIR/volume_conservation.json"
HDF_FILE="$PROJECT_DIR/Muncie.p04.hdf"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check JSON output file
JSON_EXISTS="false"
JSON_MTIME="0"
JSON_SIZE="0"
if [ -f "$OUTPUT_JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$OUTPUT_JSON")
    JSON_SIZE=$(stat -c %s "$OUTPUT_JSON")
fi

# 3. Check HDF results file (did they run the simulation?)
HDF_EXISTS="false"
HDF_MTIME="0"
HDF_SIZE="0"
if [ -f "$HDF_FILE" ]; then
    HDF_EXISTS="true"
    HDF_MTIME=$(stat -c %Y "$HDF_FILE")
    HDF_SIZE=$(stat -c %s "$HDF_FILE")
fi

# 4. Check for Python script creation (Process evidence)
SCRIPT_CREATED="false"
# Find any python script in typical locations modified after start
FOUND_SCRIPTS=$(find "$PROJECT_DIR" "$RESULTS_DIR" "$SCRIPTS_DIR" -name "*.py" -newermt "@$TASK_START" 2>/dev/null | head -1)
if [ -n "$FOUND_SCRIPTS" ]; then
    SCRIPT_CREATED="true"
fi

# 5. Create export bundle
TEMP_EXPORT=$(mktemp /tmp/export_result.XXXXXX.json)
cat > "$TEMP_EXPORT" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "json_exists": $JSON_EXISTS,
    "json_mtime": $JSON_MTIME,
    "json_size": $JSON_SIZE,
    "json_path": "$OUTPUT_JSON",
    "hdf_exists": $HDF_EXISTS,
    "hdf_mtime": $HDF_MTIME,
    "hdf_size": $HDF_SIZE,
    "script_created": $SCRIPT_CREATED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Securely move files for verifier to pick up
# We copy the result JSON to /tmp so copy_from_env can find it easily
if [ "$JSON_EXISTS" == "true" ]; then
    cp "$OUTPUT_JSON" /tmp/volume_conservation.json
    chmod 644 /tmp/volume_conservation.json
fi

mv "$TEMP_EXPORT" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result at /tmp/task_result.json"
cat /tmp/task_result.json