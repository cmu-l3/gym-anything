#!/bin/bash
echo "=== Exporting create_readonly_form results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if ODB file was modified
ODB_PATH="/home/ga/chinook.odb"
FILE_MODIFIED="false"
CURRENT_MTIME="0"
INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")

if [ -f "$ODB_PATH" ]; then
    CURRENT_MTIME=$(stat -c %Y "$ODB_PATH")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if application is running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_path": "$ODB_PATH",
    "file_modified": $FILE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Ensure the ODB file is readable for extraction by verifier
chmod 644 "$ODB_PATH"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="