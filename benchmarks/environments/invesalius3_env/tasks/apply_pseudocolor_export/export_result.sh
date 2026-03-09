#!/bin/bash
set -e
echo "=== Exporting apply_pseudocolor_export result ==="

source /workspace/scripts/task_utils.sh

# Configuration
OUTPUT_PATH="/home/ga/Documents/pseudocolor_view.png"
TASK_START_FILE="/tmp/task_start_time.txt"

# 1. Capture final state screenshot (for VLM evidence)
take_screenshot /tmp/task_final.png

# 2. Gather file statistics
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if application is still running
APP_RUNNING=$(pgrep -f "invesalius" > /dev/null && echo "true" || echo "false")

# 4. Generate JSON result
# We do mostly file stats here; heavy image analysis (color check) happens in verifier.py
# to avoid dependency issues inside the container.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $FILE_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive rights
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="