#!/system/bin/sh
# export_result.sh - Export results for verify_identify_nearest_vor
echo "=== Exporting identify_nearest_vor results ==="

OUTPUT_PATH="/sdcard/nearest_vor_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
FINAL_SCREENSHOT="/sdcard/task_final.png"

# Capture final screenshot
screencap -p "$FINAL_SCREENSHOT"

# 1. Check File Existence and Size
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(ls -l "$OUTPUT_PATH" | awk '{print $4}')
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH")
    # Escape newlines for JSON
    OUTPUT_CONTENT_JSON=$(echo "$OUTPUT_CONTENT" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_CONTENT_JSON=""
fi

# 2. Check File Timestamp (Anti-gaming)
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_PATH" ] && [ -f "$START_TIME_FILE" ]; then
    # Android usually has 'stat', but if restricted, we might depend on logic
    # Here we assume 'stat' is available or we use ls -l timestamps if needed.
    # Using a simple logic: if file exists and task started recently, we assume yes for now
    # but verifying exact timestamp in shell on simplified Android can be tricky.
    # We will let the python verifier do the heavy timestamp lifting if it pulls the file,
    # but providing a flag here is helpful.
    
    # Try stat
    TASK_START=$(cat "$START_TIME_FILE")
    FILE_TIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if Simulation Mode is likely active (rudimentary check)
# We can't easily check internal app state, but we can check if the app is running
APP_RUNNING="false"
if ps -A | grep -q "com.ds.avare"; then
    APP_RUNNING="true"
fi

# Create JSON result
# Note: creating robust JSON in shell without jq
cat > /sdcard/task_result.json <<EOF
{
  "output_exists": $OUTPUT_EXISTS,
  "output_size": $OUTPUT_SIZE,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "app_running": $APP_RUNNING,
  "output_content": "$OUTPUT_CONTENT_JSON",
  "final_screenshot_path": "$FINAL_SCREENSHOT",
  "timestamp": "$(date)"
}
EOF

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="