#!/bin/bash
echo "=== Exporting Data Quality Audit Result ==="

source /workspace/scripts/task_utils.sh

# File paths
ODB_PATH="/home/ga/chinook.odb"
SQL_PATH="/home/ga/cleanup_queries.sql"
TASK_START_FILE="/tmp/task_start_time.txt"

# Get task start time
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check ODB file status
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c%s "$ODB_PATH" 2>/dev/null || echo "0")
    ODB_MTIME=$(stat -c%Y "$ODB_PATH" 2>/dev/null || echo "0")
    
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# Check SQL log file status
SQL_EXISTS="false"
SQL_CREATED="false"
SQL_SIZE="0"

if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
    SQL_SIZE=$(stat -c%s "$SQL_PATH" 2>/dev/null || echo "0")
    SQL_MTIME=$(stat -c%Y "$SQL_PATH" 2>/dev/null || echo "0")
    
    if [ "$SQL_MTIME" -gt "$TASK_START" ]; then
        SQL_CREATED="true"
    fi
fi

# Check if LibreOffice is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "sql_exists": $SQL_EXISTS,
    "sql_created": $SQL_CREATED,
    "sql_size": $SQL_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "odb_path": "$ODB_PATH",
    "sql_path": "$SQL_PATH"
}
EOF

# Save result to /tmp/task_result.json with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="