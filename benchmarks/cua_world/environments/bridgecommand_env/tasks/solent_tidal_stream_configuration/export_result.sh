#!/bin/bash
echo "=== Exporting Solent Tidal Stream Results ==="

TARGET_FILE="/opt/bridgecommand/World/Solent/tidalstream.ini"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# Check if file exists
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    # Read file content safely (escape quotes/backslashes for JSON)
    # limit to 5KB to prevent massive file issues
    FILE_CONTENT=$(head -c 5000 "$TARGET_FILE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
    FILE_CONTENT="\"\""
fi

# Check if file was created/modified AFTER task start
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    NEWLY_CREATED="true"
else
    NEWLY_CREATED="false"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "newly_created": $NEWLY_CREATED,
    "file_content": $FILE_CONTENT,
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions for copy
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"