#!/system/bin/sh
echo "=== Exporting task results ==="

RESULT_FILE="/sdcard/interaction_result.txt"
START_TIME_FILE="/sdcard/task_start_time.txt"

# Get task start time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# Check if result file exists
if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    
    # Read content safely
    LINE1=$(sed -n '1p' "$RESULT_FILE")
    LINE2=$(sed -n '2p' "$RESULT_FILE")
    LINE3=$(sed -n '3p' "$RESULT_FILE")
    
    # Check file modification time (stat -c %Y is standard on many Android toys, strictly depends on env)
    # If stat is missing, we rely on file existence check relative to start marker
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
else
    FILE_EXISTS="false"
    LINE1=""
    LINE2=""
    LINE3=""
    FILE_MTIME="0"
fi

# Take final screenshot
screencap -p /sdcard/task_final.png 2>/dev/null || true

# Construct JSON output
# Note: manually constructing JSON string to avoid dependencies
cat > /sdcard/task_result.json <<EOF
{
    "file_exists": $FILE_EXISTS,
    "file_mtime": $FILE_MTIME,
    "task_start_time": $TASK_START,
    "line1": "$LINE1",
    "line2": "$LINE2",
    "line3": "$LINE3",
    "final_screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="