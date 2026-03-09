#!/bin/bash
# export_result.sh - Post-task hook for vapor_hazard_property_comparison

set -e
echo "=== Exporting Vapor Hazard Task Results ==="

# 1. Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Gather file statistics
OUTPUT_FILE="/home/ga/Documents/vapor_hazard_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

FILE_EXISTS=false
FILE_SIZE=0
FILE_CONTENT=""
FILE_CREATED_DURING_TASK=false

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Read content (limit size just in case)
    FILE_CONTENT=$(head -c 5000 "$OUTPUT_FILE" | base64 -w 0)
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_FILE",
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_base64": "$FILE_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"