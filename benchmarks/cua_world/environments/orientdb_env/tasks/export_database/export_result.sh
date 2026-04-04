#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting export_database task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Find the export file ---
# Agent might use slightly different naming or extension, so we look for valid candidates
EXPORT_PATH="/home/ga/exports/demodb_export.json.gz"
FOUND_FILE=""

# Priority 1: Exact match
if [ -f "$EXPORT_PATH" ]; then
    FOUND_FILE="$EXPORT_PATH"
# Priority 2: Alternative extensions in the correct directory
elif [ -d "/home/ga/exports" ]; then
    FOUND_FILE=$(find /home/ga/exports -maxdepth 1 -type f \( -name "*.json.gz" -o -name "*.gz" -o -name "*.json" \) | head -1)
fi

FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_CREATED_DURING_TASK="false"
FILE_PATH_FOUND=""

if [ -n "$FOUND_FILE" ] && [ -f "$FOUND_FILE" ]; then
    FILE_EXISTS="true"
    FILE_PATH_FOUND="$FOUND_FILE"
    FILE_SIZE_BYTES=$(stat -c%s "$FOUND_FILE" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_MTIME=$(stat -c%Y "$FOUND_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy the found file to a standard location for the verifier to pick up
    # This simplifies the python verifier code
    cp "$FOUND_FILE" /tmp/submission_export.file
    chmod 644 /tmp/submission_export.file
fi

# Check if application was running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path_found": "$FILE_PATH_FOUND",
    "file_size_bytes": $FILE_SIZE_BYTES,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="