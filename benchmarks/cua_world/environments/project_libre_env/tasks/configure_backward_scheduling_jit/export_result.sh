#!/bin/bash
echo "=== Exporting Results ==="

# 1. Capture Final State
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather File Statistics
TARGET_FILE="/home/ga/Projects/jit_schedule.xml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_EXISTS=false
FILE_SIZE=0
IS_FRESH=false

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_FRESH=true
    fi
fi

# 3. Create JSON Result
# Using a temp file to avoid permission issues if running as root vs ga
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_fresh": $IS_FRESH,
    "task_start_timestamp": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json