#!/system/bin/sh
echo "=== Exporting record_app_info results ==="

OUTPUT_FILE="/sdcard/app_info_report.txt"
GROUND_TRUTH_DIR="/data/local/tmp/ground_truth"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Analyze Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""
PARSED_VERSION=""
PARSED_EMAIL=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || date -r "$OUTPUT_FILE" +%s 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read raw content (base64 encoded to handle special chars safe in JSON)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | base64 | tr -d '\n')
    
    # Simple extraction for quick debug log
    PARSED_VERSION=$(grep -i "App Version:" "$OUTPUT_FILE" | head -1 | sed 's/.*:[[:space:]]*//')
    PARSED_EMAIL=$(grep -i "Developer Email:" "$OUTPUT_FILE" | head -1 | sed 's/.*:[[:space:]]*//')
fi

# 2. Get Ground Truth
TRUE_VERSION=$(cat "$GROUND_TRUTH_DIR/version.txt" 2>/dev/null || echo "")
TRUE_CODE=$(cat "$GROUND_TRUTH_DIR/version_code.txt" 2>/dev/null || echo "")
TRUE_EMAIL=$(cat "$GROUND_TRUTH_DIR/developer_email.txt" 2>/dev/null || echo "")

# 3. Capture Final Screenshot
screencap -p /sdcard/task_final_state.png

# 4. Create Result JSON
TEMP_JSON="/sdcard/task_result.json"

# Construct JSON string manually to avoid dependency issues
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$TEMP_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$TEMP_JSON"
echo "  \"file_content_b64\": \"$FILE_CONTENT\"," >> "$TEMP_JSON"
echo "  \"ground_truth\": {" >> "$TEMP_JSON"
echo "    \"version\": \"$TRUE_VERSION\"," >> "$TEMP_JSON"
echo "    \"version_code\": \"$TRUE_CODE\"," >> "$TEMP_JSON"
echo "    \"email\": \"$TRUE_EMAIL\"" >> "$TEMP_JSON"
echo "  }," >> "$TEMP_JSON"
echo "  \"screenshot_path\": \"/sdcard/task_final_state.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

echo "Export complete. Result saved to $TEMP_JSON"
cat "$TEMP_JSON"