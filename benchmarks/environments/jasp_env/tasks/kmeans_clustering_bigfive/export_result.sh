#!/bin/bash
echo "=== Exporting JASP K-Means Result ==="

# 1. Define Paths
OUTPUT_FILE="/home/ga/Documents/JASP/BigFive_KMeans.jasp"
RESULT_JSON="/tmp/task_result.json"

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Gather File Statistics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check if JASP is still running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
# We don't parse the binary .jasp file here; verifier.py will handle it via copy_from_env
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_file_path": "$OUTPUT_FILE",
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Permissions
chmod 666 "$RESULT_JSON"

echo "Result metadata saved to $RESULT_JSON"
echo "=== Export Complete ==="