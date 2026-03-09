#!/bin/bash
echo "=== Exporting Chinook Partner Sales ETL Results ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_FILE="/home/ga/Documents/exports/festival_sales_exceptions.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Staging Table exists and get count
STAGING_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM festival_sales_import;" 2>/dev/null || echo "-1")
echo "Staging table count: $STAGING_COUNT"

# 2. Check Valid Table schema and content
# We export the table schema and data to JSON for the python verifier
# This avoids complicated parsing in bash

# Get schema info
VALID_SCHEMA=$(sqlite3 "$DB_PATH" "PRAGMA table_info(valid_festival_sales);" 2>/dev/null)

# Get valid rows count
VALID_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM valid_festival_sales;" 2>/dev/null || echo "-1")

# Get foreign key validation data
# We check how many rows in the result table actually match the source tables.
# This query returns the count of VALID rows that are correctly linked.
# If the agent inserted bad IDs, this count will be lower than VALID_COUNT.
INTEGRITY_CHECK_COUNT=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) 
    FROM valid_festival_sales v
    JOIN customers c ON v.CustomerId = c.CustomerId
    JOIN tracks t ON v.TrackId = t.TrackId
;" 2>/dev/null || echo "0")

echo "Valid table count: $VALID_COUNT"
echo "Integrity check count: $INTEGRITY_CHECK_COUNT"

# 3. Check Exception File
EXCEPTION_FILE_EXISTS="false"
EXCEPTION_ROW_COUNT=0
if [ -f "$EXPORT_FILE" ]; then
    EXCEPTION_FILE_EXISTS="true"
    # Subtract 1 for header
    TOTAL_LINES=$(wc -l < "$EXPORT_FILE")
    EXCEPTION_ROW_COUNT=$((TOTAL_LINES - 1))
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
fi

# 4. Check App State
APP_RUNNING=$(is_dbeaver_running)

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "staging_table_count": $STAGING_COUNT,
    "valid_table_count": $VALID_COUNT,
    "integrity_check_count": $INTEGRITY_CHECK_COUNT,
    "exception_file_exists": $EXCEPTION_FILE_EXISTS,
    "exception_row_count": $EXCEPTION_ROW_COUNT,
    "file_created_during_task": ${FILE_CREATED_DURING_TASK:-false},
    "app_was_running": $APP_RUNNING,
    "valid_schema_dump": "$(echo "$VALID_SCHEMA" | tr '\n' '|' | sed 's/"/\\"/g')"
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="