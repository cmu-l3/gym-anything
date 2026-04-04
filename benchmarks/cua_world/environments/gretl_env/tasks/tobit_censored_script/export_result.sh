#!/bin/bash
echo "=== Exporting tobit_censored_script results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_FILE="/home/ga/Documents/gretl_output/tobit_ols_comparison.txt"
SCRIPT_FILE="/home/ga/Documents/gretl_output/tobit_analysis.inp"

# Check Output File
OUTPUT_EXISTS="false"
OUTPUT_CREATED_IN_TASK="false"
OUTPUT_SIZE=0
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_IN_TASK="true"
    fi
fi

# Check Script File
SCRIPT_EXISTS="false"
SCRIPT_CREATED_IN_TASK="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$SCRIPT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_CREATED_IN_TASK="true"
    fi
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_created_in_task": $OUTPUT_CREATED_IN_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_in_task": $SCRIPT_CREATED_IN_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe copy to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"