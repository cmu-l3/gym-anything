#!/bin/bash
echo "=== Exporting Royalty Calculation Results ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/royalty_summary.csv"
SQL_PATH="/home/ga/Documents/scripts/royalty_calculation.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Files
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_SIZE=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
    FILE_TIME=$(stat -c %Y "$CSV_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

SQL_EXISTS="false"
SQL_CREATED_DURING_TASK="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$SQL_PATH")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        SQL_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Database Connection in DBeaver Config
CONNECTION_FOUND="false"
CONNECTION_NAME=""
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Simple check for the connection name in the json file
    if grep -q "ChinookRoyalty" "$DBEAVER_CONFIG"; then
        CONNECTION_FOUND="true"
        CONNECTION_NAME="ChinookRoyalty"
    fi
fi

# 3. Extract Database State (Tables and Content)
# We export relevant data to JSON for the verifier to analyze programmatically

# Check royalty_rates
RATES_TABLE_EXISTS="false"
RATES_DATA="[]"
if sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='royalty_rates';" | grep -q "1"; then
    RATES_TABLE_EXISTS="true"
    # Export rows as JSON object list
    RATES_DATA=$(sqlite3 "$DB_PATH" ".mode json" "SELECT * FROM royalty_rates ORDER BY MinRevenue;")
fi

# Check artist_monthly_royalties
ROYALTIES_TABLE_EXISTS="false"
ROYALTIES_SCHEMA_VALID="false"
ROYALTIES_ROW_COUNT=0
SAMPLE_ROYALTIES="[]"

if sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='artist_monthly_royalties';" | grep -q "1"; then
    ROYALTIES_TABLE_EXISTS="true"
    ROYALTIES_ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM artist_monthly_royalties;")
    
    # Check for required columns in schema
    SCHEMA=$(sqlite3 "$DB_PATH" "PRAGMA table_info(artist_monthly_royalties);")
    if echo "$SCHEMA" | grep -q "GrossRevenue" && echo "$SCHEMA" | grep -q "RoyaltyAmount" && echo "$SCHEMA" | grep -q "TierName"; then
        ROYALTIES_SCHEMA_VALID="true"
    fi

    # Export a sample of rows for math verification (first 20 rows)
    SAMPLE_ROYALTIES=$(sqlite3 "$DB_PATH" ".mode json" "SELECT * FROM artist_monthly_royalties LIMIT 20;")
fi

# 4. Read CSV Content (Headers and First few lines)
CSV_HEADER=""
CSV_SAMPLE=""
if [ "$CSV_EXISTS" = "true" ]; then
    CSV_HEADER=$(head -n 1 "$CSV_PATH")
    CSV_SAMPLE=$(head -n 5 "$CSV_PATH" | tail -n 4)
fi

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "connection_found": $CONNECTION_FOUND,
    "connection_name": "$CONNECTION_NAME",
    "csv": {
        "exists": $CSV_EXISTS,
        "created_during_task": $CSV_CREATED_DURING_TASK,
        "size": $CSV_SIZE,
        "header": "$CSV_HEADER"
    },
    "sql_script": {
        "exists": $SQL_EXISTS,
        "created_during_task": $SQL_CREATED_DURING_TASK
    },
    "database": {
        "rates_table_exists": $RATES_TABLE_EXISTS,
        "rates_data": $RATES_DATA,
        "royalties_table_exists": $ROYALTIES_TABLE_EXISTS,
        "royalties_row_count": $ROYALTIES_ROW_COUNT,
        "royalties_schema_valid": $ROYALTIES_SCHEMA_VALID,
        "sample_royalties": $SAMPLE_ROYALTIES
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="