#!/system/bin/sh
echo "=== Exporting Capecitabine Audit Result ==="

OUTPUT_PATH="/sdcard/Download/capecitabine_audit.txt"
MARKER_PATH="/sdcard/task_start_marker"
RESULT_JSON="/sdcard/task_result.json"

# 1. Check if output file exists
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    # Get file size
    OUTPUT_SIZE=$(ls -l "$OUTPUT_PATH" | awk '{print $4}')
    
    # Check if created after task start (simple check: if marker exists)
    if [ -f "$MARKER_PATH" ]; then
        # In Android shell, comparing timestamps is tricky without stat %Y.
        # We rely on the fact that we deleted it in setup.
        # If it exists now, it was created during the task.
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="unknown"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# 2. Capture final state screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot captured."

# 3. Dump UI hierarchy (useful for debugging, though verification uses VLM)
uiautomator dump /sdcard/ui_dump.xml >/dev/null 2>&1

# 4. Construct JSON result
# Note: JSON construction in sh is manual
echo "{" > "$RESULT_JSON"
echo "  \"output_exists\": $OUTPUT_EXISTS," >> "$RESULT_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"output_size_bytes\": $OUTPUT_SIZE," >> "$RESULT_JSON"
echo "  \"timestamp\": \"$(date)\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON saved to $RESULT_JSON"
cat "$RESULT_JSON"

echo "=== Export Complete ==="