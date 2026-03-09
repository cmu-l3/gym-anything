#!/system/bin/sh
echo "=== Exporting Analgesic Investigation Results ==="

# Capture final state
screencap -p /sdcard/task_final.png

# Get timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check output file
OUTPUT_PATH="/sdcard/abiraterone_pain_audit.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    # Read content, escaping quotes for JSON safety
    FILE_CONTENT=$(cat "$OUTPUT_PATH" | sed 's/"/\\"/g' | tr '\n' ' ')
    
    # Check modification time (simple check since Android stat might vary)
    # We rely on the fact we deleted it in setup
    FILE_CREATED_DURING_TASK="true" 
fi

# Create result JSON
# Note: Using a temporary file approach compatible with Android shell
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"file_content\": \"$FILE_CONTENT\"," >> /sdcard/task_result.json
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Export complete. Result saved to /sdcard/task_result.json"