#!/bin/bash
echo "=== Exporting run_dms_vawt_simulation results ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/projects/vawt_dms_result.wpa"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
CONTAINS_DMS_DATA="false"
CONTAINS_TSR_RANGE="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Content Check: Scan for DMS related keywords in the XML/Text project file
    # WPA files are text based. Look for "DMS", "Lambda", "Cp"
    # QBlade v0.96 saves project data in a custom text format
    if grep -qi "DMS" "$OUTPUT_PATH"; then
        CONTAINS_DMS_DATA="true"
    fi
    
    # Check for specific TSR range parameters (start=1, end=8)
    # The format might vary, but we look for the numbers in context
    # or just existence of simulation results
    if grep -q "1.0000" "$OUTPUT_PATH" && grep -q "8.0000" "$OUTPUT_PATH"; then
        CONTAINS_TSR_RANGE="true"
    fi
fi

# Check if app is running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "contains_dms_data": $CONTAINS_DMS_DATA,
    "contains_tsr_range": $CONTAINS_TSR_RANGE,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to public location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="