#!/bin/bash
echo "=== Exporting RFM Analysis Results ==="

source /workspace/scripts/task_utils.sh

# Configuration
CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
EXPORT_CSV="/home/ga/Documents/exports/rfm_segments.csv"
EXPORT_SQL="/home/ga/Documents/scripts/rfm_analysis.sql"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/rfm_final.png

# Check 1: CSV Export
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CONTENT=""
CSV_CREATED_DURING_TASK="false"

if [ -f "$EXPORT_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$EXPORT_CSV")
    # Read content for verifier (base64 to handle newlines/special chars safely in JSON)
    CSV_CONTENT=$(base64 -w 0 "$EXPORT_CSV")
    
    FILE_TIME=$(stat -c%Y "$EXPORT_CSV")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# Check 2: SQL Script
SQL_EXISTS="false"
SQL_CONTENT=""
if [ -f "$EXPORT_SQL" ]; then
    SQL_EXISTS="true"
    SQL_CONTENT=$(base64 -w 0 "$EXPORT_SQL")
fi

# Check 3: Database Object (Table or View)
DB_OBJECT_EXISTS="false"
DB_OBJECT_TYPE=""
DB_ROW_COUNT=0

if [ -f "$CHINOOK_DB" ]; then
    # Check for Table
    if sqlite3 "$CHINOOK_DB" "SELECT 1 FROM sqlite_master WHERE name='customer_rfm' AND type='table';" | grep -q 1; then
        DB_OBJECT_EXISTS="true"
        DB_OBJECT_TYPE="table"
    # Check for View
    elif sqlite3 "$CHINOOK_DB" "SELECT 1 FROM sqlite_master WHERE name='customer_rfm' AND type='view';" | grep -q 1; then
        DB_OBJECT_EXISTS="true"
        DB_OBJECT_TYPE="view"
    fi

    if [ "$DB_OBJECT_EXISTS" = "true" ]; then
        DB_ROW_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM customer_rfm;" 2>/dev/null || echo "0")
    fi
fi

# Check 4: App State
APP_RUNNING=$(is_dbeaver_running)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/rfm_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_content_b64": "$CSV_CONTENT",
    "sql_exists": $SQL_EXISTS,
    "sql_content_b64": "$SQL_CONTENT",
    "db_object_exists": $DB_OBJECT_EXISTS,
    "db_object_type": "$DB_OBJECT_TYPE",
    "db_row_count": $DB_ROW_COUNT,
    "app_running": $APP_RUNNING,
    "task_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/rfm_task_result.json
chmod 666 /tmp/rfm_task_result.json

echo "Export complete. Result saved to /tmp/rfm_task_result.json"