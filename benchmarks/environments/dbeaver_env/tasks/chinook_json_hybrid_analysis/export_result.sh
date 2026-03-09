#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather file timestamps and existence info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_PATH="/home/ga/Documents/exports/high_energy_tracks.csv"
SQL_PATH="/home/ga/Documents/scripts/json_analysis.sql"

# Check DB modification
DB_MODIFIED="false"
if [ -f "$DB_PATH" ]; then
    DB_MTIME=$(stat -c %Y "$DB_PATH" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi
fi

# Check Export File
EXPORT_EXISTS="false"
EXPORT_CREATED_DURING="false"
if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        EXPORT_CREATED_DURING="true"
    fi
fi

# Check SQL Script
SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# 3. Create JSON Result
# We will verify the actual data integrity in python by copying the DB file,
# so we just pass basic metadata here.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_exists": $([ -f "$DB_PATH" ] && echo "true" || echo "false"),
    "db_modified": $DB_MODIFIED,
    "export_exists": $EXPORT_EXISTS,
    "export_created_during_task": $EXPORT_CREATED_DURING,
    "sql_exists": $SQL_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="