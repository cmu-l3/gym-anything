#!/system/bin/sh
echo "=== Exporting check_statin_interaction results ==="

RESULT_FILE="/sdcard/interaction_result.txt"
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot for VLM verification
screencap -p /sdcard/task_final.png

# 2. Check Result File Status
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
LINE1=""
LINE2=""
LINE3=""
LINE4=""

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content
    LINE1=$(head -n 1 "$RESULT_FILE")
    LINE2=$(head -n 2 "$RESULT_FILE" | tail -n 1)
    LINE3=$(head -n 3 "$RESULT_FILE" | tail -n 1)
    LINE4=$(head -n 4 "$RESULT_FILE" | tail -n 1)
fi

# 3. Create JSON payload
# We construct JSON manually using echo to avoid dependency issues on minimal Android shells
# We use sed to escape quotes to prevent JSON breakage
SAFE_L1=$(echo "$LINE1" | sed 's/"/\\"/g')
SAFE_L2=$(echo "$LINE2" | sed 's/"/\\"/g')
SAFE_L3=$(echo "$LINE3" | sed 's/"/\\"/g')
SAFE_L4=$(echo "$LINE4" | sed 's/"/\\"/g')

echo "{
  \"task_start\": $START_TIME,
  \"task_end\": $TASK_END,
  \"file_exists\": $FILE_EXISTS,
  \"file_created_during_task\": $FILE_CREATED_DURING_TASK,
  \"content\": {
    \"line1\": \"$SAFE_L1\",
    \"line2\": \"$SAFE_L2\",
    \"line3\": \"$SAFE_L3\",
    \"line4\": \"$SAFE_L4\"
  },
  \"screenshot_path\": \"/sdcard/task_final.png\"
}" > /sdcard/task_result.json

echo "Export complete. JSON saved to /sdcard/task_result.json"