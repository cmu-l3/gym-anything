#!/bin/bash
echo "=== Exporting query_long_rock_tracks result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Check if ODB file was modified
ODB_PATH="/home/ga/chinook.odb"
INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")
CURRENT_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")

if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
    FILE_MODIFIED="true"
else
    FILE_MODIFIED="false"
fi

# Check if LO is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# Prepare ODB for export (copy to /tmp so verifier can access it via copy_from_env)
# The verifier needs to parse content.xml inside the ODB zip
cp "$ODB_PATH" /tmp/result_chinook.odb
chmod 644 /tmp/result_chinook.odb

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "odb_path": "/tmp/result_chinook.odb",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="