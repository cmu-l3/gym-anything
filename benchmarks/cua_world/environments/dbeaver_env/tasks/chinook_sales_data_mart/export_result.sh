#!/bin/bash
# Export script for chinook_sales_data_mart task
# Verifies the created database structure and content

echo "=== Exporting Chinook Sales Data Mart Result ==="

source /workspace/scripts/task_utils.sh

TARGET_DB="/home/ga/Documents/databases/chinook_dw.db"
SCRIPT_PATH="/home/ga/Documents/scripts/etl_sales_mart.sql"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if DB exists
DB_EXISTS="false"
TABLE_EXISTS="false"
ROW_COUNT=0
COLUMNS_JSON="[]"
SAMPLE_DATA="{}"
CROSS_BORDER_SUM=0
QUARTER_CHECK="fail"
ARTIST_CHECK="fail"
SCRIPT_EXISTS="false"

if [ -f "$TARGET_DB" ]; then
    DB_EXISTS="true"
    
    # Check for table existence
    if sqlite3 "$TARGET_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='fact_sales';" | grep -q "fact_sales"; then
        TABLE_EXISTS="true"
        
        # Get Row Count
        ROW_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM fact_sales;" 2>/dev/null || echo 0)
        
        # Get Column Info
        # Using python to format sqlite PRAGMA output to JSON list of column names
        COLUMNS_JSON=$(sqlite3 "$TARGET_DB" "PRAGMA table_info(fact_sales);" | awk -F'|' '{print "\""$2"\""}' | paste -sd, - | sed 's/^/[/;s/$/]/')
        
        # Verify Sample Data (InvoiceLineId 1)
        # Truth: InvoiceLineId=1, Track=For Those About To Rock..., Artist=AC/DC, Date=2009-01-01, Q=2009-Q1
        SAMPLE_DATA=$(sqlite3 -json "$TARGET_DB" "SELECT * FROM fact_sales WHERE InvoiceLineId=1;" 2>/dev/null || echo "{}")
        
        # Verify Cross Border Logic Sum
        # In Chinook, many customers are international vs rep. Just getting a checksum.
        CROSS_BORDER_SUM=$(sqlite3 "$TARGET_DB" "SELECT SUM(IsCrossBorder) FROM fact_sales;" 2>/dev/null || echo 0)
        
        # Logic Checks via SQL directly
        # Check Quarter format
        QUARTER_FORMAT_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM fact_sales WHERE SalesQuarter LIKE '____-Q_';" 2>/dev/null || echo 0)
        if [ "$QUARTER_FORMAT_COUNT" -eq "$ROW_COUNT" ] && [ "$ROW_COUNT" -gt 0 ]; then
            QUARTER_CHECK="pass"
        fi
        
        # Check Artist Join (Sample check: Track 'Put The Finger On You' should be 'AC/DC')
        ARTIST_NAME=$(sqlite3 "$TARGET_DB" "SELECT ArtistName FROM fact_sales WHERE TrackName='Put The Finger On You' LIMIT 1;" 2>/dev/null)
        if [ "$ARTIST_NAME" == "AC/DC" ]; then
            ARTIST_CHECK="pass"
        fi
    fi
fi

# 3. Check if script exists
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi

# 4. Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)
FILE_TIME=$(stat -c%Y "$TARGET_DB" 2>/dev/null || echo 0)
CREATED_DURING_TASK="false"
if [ "$FILE_TIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# 5. Build Result JSON
cat > /tmp/task_result.json << EOF
{
    "db_exists": $DB_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "row_count": $ROW_COUNT,
    "columns": $COLUMNS_JSON,
    "sample_row": $SAMPLE_DATA,
    "cross_border_sum": $CROSS_BORDER_SUM,
    "quarter_check": "$QUARTER_CHECK",
    "artist_check": "$ARTIST_CHECK",
    "script_exists": $SCRIPT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "task_start": $TASK_START,
    "file_timestamp": $FILE_TIME
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json