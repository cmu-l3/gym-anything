#!/system/bin/sh
# Export script for verify_landscape_layout task
# Runs on Android device

echo "=== Exporting Task Results ==="

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

PROOF_FILE="/sdcard/landscape_proof.png"
REPORT_FILE="/sdcard/rotation_report.txt"

# 1. Check Screenshot
PROOF_EXISTS="false"
PROOF_SIZE="0"
if [ -f "$PROOF_FILE" ]; then
    PROOF_MTIME=$(stat -c %Y "$PROOF_FILE" 2>/dev/null || echo "0")
    if [ "$PROOF_MTIME" -ge "$TASK_START" ]; then
        PROOF_EXISTS="true"
        PROOF_SIZE=$(stat -c %s "$PROOF_FILE")
    fi
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_CONTENT=$(cat "$REPORT_FILE")
    fi
fi

# 3. Check Final Rotation State (Should be 0 / Portrait)
FINAL_ROTATION=$(settings get system user_rotation 2>/dev/null | tr -d '\r\n')
ROTATION_RESTORED="false"
if [ "$FINAL_ROTATION" = "0" ]; then
    ROTATION_RESTORED="true"
fi

# 4. Check if App is Still Running (Not Crashed)
APP_RUNNING="false"
if pidof com.robert.fcView > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
JSON_FILE="/sdcard/task_result.json"
echo "{" > "$JSON_FILE"
echo "  \"task_start\": $TASK_START," >> "$JSON_FILE"
echo "  \"proof_exists\": $PROOF_EXISTS," >> "$JSON_FILE"
echo "  \"proof_size\": $PROOF_SIZE," >> "$JSON_FILE"
echo "  \"report_exists\": $REPORT_EXISTS," >> "$JSON_FILE"
echo "  \"report_content\": \"$REPORT_CONTENT\"," >> "$JSON_FILE"
echo "  \"final_rotation\": \"$FINAL_ROTATION\"," >> "$JSON_FILE"
echo "  \"rotation_restored\": $ROTATION_RESTORED," >> "$JSON_FILE"
echo "  \"app_running\": $APP_RUNNING" >> "$JSON_FILE"
echo "}" >> "$JSON_FILE"

echo "Result saved to $JSON_FILE"
cat "$JSON_FILE"
echo "=== Export Complete ==="