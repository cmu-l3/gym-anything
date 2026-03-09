#!/bin/bash
echo "=== Exporting Attach Source result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_end.png

PROJECT_DIR="/home/ga/eclipse-workspace/TreatmentPlanner"
CLASSPATH_FILE="$PROJECT_DIR/.classpath"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if .classpath exists
CLASSPATH_EXISTS="false"
CLASSPATH_MODIFIED="false"
CLASSPATH_CONTENT=""

if [ -f "$CLASSPATH_FILE" ]; then
    CLASSPATH_EXISTS="true"
    CLASSPATH_CONTENT=$(cat "$CLASSPATH_FILE")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$CLASSPATH_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CLASSPATH_MODIFIED="true"
    fi
fi

# Check if Eclipse is running
APP_RUNNING=$(pgrep -f "eclipse" > /dev/null && echo "true" || echo "false")

# Escape content for JSON
CONTENT_ESCAPED=$(echo "$CLASSPATH_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "classpath_exists": $CLASSPATH_EXISTS,
    "classpath_modified": $CLASSPATH_MODIFIED,
    "classpath_content": $CONTENT_ESCAPED,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Save result safely
write_json_result "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="