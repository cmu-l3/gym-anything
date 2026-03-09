#!/system/bin/sh
# Export script for single_phase_power_calc task
# Runs on Android device

echo "=== Exporting Single Phase Power Results ==="

RESULT_JSON="/sdcard/task_result.json"
OUTPUT_FILE="/sdcard/power_analysis.txt"
PACKAGE="com.hsn.electricalcalculations"

# 1. Check if output file exists and read it
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Read content, escape double quotes and newlines for JSON
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | sed 's/"/\\"/g' | tr '\n' '|')
    
    # Get modification time (stat might not be available on all Androids, using ls -l as fallback)
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null)
    if [ -z "$FILE_MTIME" ]; then
        # Fallback if stat fails
        FILE_MTIME="1" 
    fi
fi

# 2. Check if app is running
APP_RUNNING="false"
if ps -A | grep -q "$PACKAGE"; then
    APP_RUNNING="true"
fi

# 3. Capture final screenshot
screencap -p /sdcard/task_final.png

# 4. Construct JSON result
# Note: Simple string concatenation to avoid dependency on jq
echo "{" > "$RESULT_JSON"
echo "  \"file_exists\": $FILE_EXISTS," >> "$RESULT_JSON"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$RESULT_JSON"
echo "  \"file_mtime\": $FILE_MTIME," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"timestamp\": $(date +%s)" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"