#!/bin/bash
# Export for implement_qc_workflow
set -e

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if database file was modified
ODB_PATH="/home/ga/chinook.odb"
ODB_MODIFIED="false"
if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 2. Extract the HSQLDB script file from the ODB (which is a ZIP)
# This script contains the CREATE TABLE and INSERT statements representing the DB state.
echo "Extracting database script from ODB..."
rm -f /tmp/db_script.sql
if [ -f "$ODB_PATH" ]; then
    # ODB is a zip file. The HSQLDB script is usually at database/script
    unzip -p "$ODB_PATH" database/script > /tmp/db_script.sql 2>/dev/null || true
fi

SCRIPT_EXISTS="false"
SCRIPT_SIZE="0"
if [ -s /tmp/db_script.sql ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c %s /tmp/db_script.sql)
fi

# 3. Check if App is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_modified": $ODB_MODIFIED,
    "db_script_extracted": $SCRIPT_EXISTS,
    "db_script_path": "/tmp/db_script.sql",
    "db_script_size": $SCRIPT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move results to final location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 644 /tmp/db_script.sql 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="