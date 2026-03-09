#!/bin/bash
echo "=== Exporting create_master_detail_form results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ODB_PATH="/home/ga/chinook.odb"

# Check if ODB exists and was modified
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    CURRENT_MTIME=$(stat -c %Y "$ODB_PATH")
    INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")
    
    # Check if modification time is strictly greater than initial
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        ODB_MODIFIED="true"
    fi
fi

# Check if LibreOffice is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "app_running": $APP_RUNNING,
    "odb_path": "$ODB_PATH"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Ensure ODB is readable by ga (and thus copyable by verifier)
chmod 644 "$ODB_PATH"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="