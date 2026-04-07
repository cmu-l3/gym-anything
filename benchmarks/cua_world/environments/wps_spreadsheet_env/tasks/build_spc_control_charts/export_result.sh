#!/bin/bash
echo "=== Exporting SPC Control Charts task ==="

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

FILE_PATH="/home/ga/Documents/piston_ring_measurements.xlsx"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$FILE_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    
    # Check if the file was saved AFTER the task started
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        MODIFIED="true"
    else
        MODIFIED="false"
    fi
    EXISTS="true"
else
    EXISTS="false"
    MODIFIED="false"
    FILE_SIZE=0
fi

cat > /tmp/task_result.json << EOF
{
    "file_exists": $EXISTS,
    "file_modified": $MODIFIED,
    "file_size": $FILE_SIZE
}
EOF
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="