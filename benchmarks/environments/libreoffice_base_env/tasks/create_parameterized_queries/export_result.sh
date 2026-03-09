#!/bin/bash
echo "=== Exporting create_parameterized_queries results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target ODB file
ODB_PATH="/home/ga/chinook.odb"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check ODB file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    
    # Check if modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Copy the ODB file to a temp location for the verifier to download
    # (The verifier runs on the host and needs to copy files out)
    cp "$ODB_PATH" /tmp/submission.odb
    chmod 644 /tmp/submission.odb
fi

# 3. Check if LibreOffice is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 4. Create JSON result
# We don't analyze the ODB content here (Python verifier is better for XML parsing)
# We just export metadata.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "submission_path": "/tmp/submission.odb",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"