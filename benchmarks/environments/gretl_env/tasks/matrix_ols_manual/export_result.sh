#!/bin/bash
echo "=== Exporting matrix_ols_manual results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_DIR="/home/ga/Documents/gretl_output"
RESULT_FILE="$OUTPUT_DIR/matrix_ols_results.txt"
SCRIPT_FILE="$OUTPUT_DIR/matrix_ols_script.inp"

# Check Results File
RESULT_EXISTS="false"
RESULT_CREATED_DURING="false"
RESULT_SIZE="0"
if [ -f "$RESULT_FILE" ]; then
    RESULT_EXISTS="true"
    RESULT_SIZE=$(stat -c %s "$RESULT_FILE")
    RESULT_MTIME=$(stat -c %Y "$RESULT_FILE")
    if [ "$RESULT_MTIME" -gt "$TASK_START" ]; then
        RESULT_CREATED_DURING="true"
    fi
fi

# Check Script File
SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_FILE")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_CREATED_DURING="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "result_file_exists": $RESULT_EXISTS,
    "result_created_during_task": $RESULT_CREATED_DURING,
    "result_file_size": $RESULT_SIZE,
    "script_file_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export complete ==="