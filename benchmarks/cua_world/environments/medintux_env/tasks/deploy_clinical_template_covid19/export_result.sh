#!/bin/bash
echo "=== Exporting deploy_clinical_template_covid19 result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Locate the file created by the agent
# We search in the Wine prefix
echo "Searching for created template file..."
FOUND_FILE=$(find /home/ga/.wine/drive_c -name "Depistage_COVID19.html" 2>/dev/null | head -1)

FILE_EXISTS="false"
DIR_CREATED="false"
FILE_CONTENT=""
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
PARENT_DIR_NAME=""

if [ -n "$FOUND_FILE" ]; then
    echo "File found at: $FOUND_FILE"
    FILE_EXISTS="true"
    
    # Check parent directory name
    PARENT_DIR=$(dirname "$FOUND_FILE")
    PARENT_DIR_NAME=$(basename "$PARENT_DIR")
    
    if [ "$PARENT_DIR_NAME" == "Protocoles_Urgence" ]; then
        DIR_CREATED="true"
    fi
    
    # Check file modification time
    FILE_MTIME=$(stat -c %Y "$FOUND_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    FILE_SIZE=$(stat -c %s "$FOUND_FILE" 2>/dev/null || echo "0")
    
    # Read content (base64 encode to safely pass to JSON)
    # We only need the first few KB for verification
    FILE_CONTENT=$(head -c 5000 "$FOUND_FILE" | base64 -w 0)
else
    echo "File Depistage_COVID19.html not found."
fi

# 2. Check if MedinTux is running
APP_RUNNING=$(pgrep -f "Manager.exe" > /dev/null && echo "true" || echo "false")

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "${FOUND_FILE:-}",
    "directory_correct": $DIR_CREATED,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "file_content_b64": "$FILE_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="