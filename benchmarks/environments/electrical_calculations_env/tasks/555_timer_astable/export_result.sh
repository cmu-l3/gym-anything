#!/system/bin/sh
echo "=== Exporting 555 Timer Astable results ==="

RESULTS_FILE="/sdcard/555_timer_results.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"
JSON_OUTPUT="/sdcard/task_result.json"

# Get task start time
TASK_START=0
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
fi

# Initialize variables
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""
FREQ_VAL=""
DUTY_VAL=""
THIGH_VAL=""
TLOW_VAL=""

# Check file status
if [ -f "$RESULTS_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check modification time
    FILE_MOD=$(stat -c %Y "$RESULTS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MOD" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content
    FILE_CONTENT=$(cat "$RESULTS_FILE")
    
    # Simple extraction using grep/sed (Android shell might be limited, so keep it simple)
    # We read the raw content into the JSON, parsing happens in python verifier
else
    echo "Results file not found at $RESULTS_FILE"
fi

# Check if app is running (in foreground or background)
APP_RUNNING="false"
if ps -A | grep -q "com.hsn.electricalcalculations"; then
    APP_RUNNING="true"
fi

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Create JSON output
# Note: dealing with newlines in FILE_CONTENT for JSON safety
SAFE_CONTENT=$(echo "$FILE_CONTENT" | sed 's/"/\\"/g' | tr '\n' '\\n')

echo "{" > "$JSON_OUTPUT"
echo "  \"task_start\": $TASK_START," >> "$JSON_OUTPUT"
echo "  \"file_exists\": $FILE_EXISTS," >> "$JSON_OUTPUT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$JSON_OUTPUT"
echo "  \"app_running\": $APP_RUNNING," >> "$JSON_OUTPUT"
echo "  \"file_content\": \"$SAFE_CONTENT\"" >> "$JSON_OUTPUT"
echo "}" >> "$JSON_OUTPUT"

echo "=== Export complete ==="
cat "$JSON_OUTPUT"