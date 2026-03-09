#!/system/bin/sh
# Export script for inventory_analgesics_for_brigatinib task

echo "=== Exporting Inventory Task Result ==="

OUTPUT_FILE="/sdcard/Download/brigatinib_analgesics_inventory.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
RESULT_JSON="/sdcard/task_result.json"
FINAL_SCREENSHOT="/sdcard/final_screenshot.png"

# 1. Capture final screenshot
screencap -p "$FINAL_SCREENSHOT"
echo "Captured final screenshot"

# 2. Check output file details
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || ls -l "$OUTPUT_FILE" | awk '{print $4}')
    # Read content (escape quotes for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# 3. Check timestamps (Anti-gaming)
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
FILE_MOD_TIME="0"
CREATED_DURING_TASK="false"

if [ "$FILE_EXISTS" = "true" ]; then
    # Get modification time (epoch)
    FILE_MOD_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Simple check: if file mod time > task start time
    if [ "$FILE_MOD_TIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 4. Create JSON result
# Note: standard echo on Android might interpret -e, careful with json construction
echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_size\": $FILE_SIZE," >> "$RESULT_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$RESULT_JSON"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"timestamp\": $(date +%s)" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="