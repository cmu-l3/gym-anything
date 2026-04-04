#!/bin/bash
echo "=== Exporting fix_xml_config_errors result ==="

source /workspace/scripts/task_utils.sh

# Paths
PROJECT_DIR="/home/ga/eclipse-workspace/RadOncPhysics"
XML_FILE="$PROJECT_DIR/beam_model.xml"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
XML_CONTENT=""
FILE_MTIME="0"

if [ -f "$XML_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$XML_FILE" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi

    # Read content for verification
    XML_CONTENT=$(cat "$XML_FILE")
fi

# Determine if Eclipse is still running
APP_RUNNING=$(pgrep -f "eclipse" > /dev/null && echo "true" || echo "false")

# Escape XML content for JSON
XML_ESCAPED=$(echo "$XML_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "xml_content": $XML_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
write_json_result "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="