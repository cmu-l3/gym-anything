#!/bin/bash
echo "=== Exporting Northwind DB Diff Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
CSV_FILE="$EXPORT_DIR/db_diff_report.csv"
SQL_FILE="$SCRIPTS_DIR/sync_prod_to_staging.sql"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Files Existence & Timestamps
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    F_TIME=$(stat -c %Y "$CSV_FILE")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

SQL_EXISTS="false"
SQL_CREATED_DURING_TASK="false"
if [ -f "$SQL_FILE" ]; then
    SQL_EXISTS="true"
    F_TIME=$(stat -c %Y "$SQL_FILE")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        SQL_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check DBeaver Connections
# We look for "NorthwindProd" and "NorthwindStaging" in data-sources.json
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
DATA_SOURCES="$CONFIG_DIR/data-sources.json"
CONN_PROD_EXISTS="false"
CONN_STAGING_EXISTS="false"

if [ -f "$DATA_SOURCES" ]; then
    # Simple grep check, python verifier will do robust JSON parsing if needed,
    # but let's do a quick python check here to populate the JSON
    python3 -c "
import json
try:
    with open('$DATA_SOURCES') as f:
        data = json.load(f)
    conns = data.get('connections', {})
    prod = any('NorthwindProd' in c.get('name', '') for c in conns.values())
    staging = any('NorthwindStaging' in c.get('name', '') for c in conns.values())
    print(f'{prod}|{staging}')
except:
    print('False|False')
" > /tmp/conn_check.txt
    
    CONN_PROD_EXISTS=$(cut -d'|' -f1 /tmp/conn_check.txt)
    CONN_STAGING_EXISTS=$(cut -d'|' -f2 /tmp/conn_check.txt)
fi

# 3. Verify SQL Script Effectiveness (Anti-Gaming / Robustness)
# We try to apply the agent's SQL script to a COPY of Prod and check if it matches Staging
SYNC_SUCCESS="false"
SYNC_ERROR=""

if [ "$SQL_EXISTS" = "true" ]; then
    echo "Testing SQL sync script..."
    TEST_DB="/tmp/test_sync.db"
    cp "/home/ga/Documents/databases/northwind_prod.db" "$TEST_DB"
    
    # Try to run the script
    if sqlite3 "$TEST_DB" < "$SQL_FILE" 2> /tmp/sql_error.log; then
        echo "SQL executed successfully."
        # Compare checksums of critical tables between TEST_DB and STAGING_DB
        # We dump specific tables to avoid binary differences from ordering/metadata
        
        TABLES="Product Customer Category OrderDetail"
        MATCH_COUNT=0
        
        for T in $TABLES; do
            DUMP_STAGING=$(sqlite3 "/home/ga/Documents/databases/northwind_staging.db" "SELECT * FROM $T ORDER BY 1;" | md5sum)
            DUMP_TEST=$(sqlite3 "$TEST_DB" "SELECT * FROM $T ORDER BY 1;" | md5sum)
            
            if [ "$DUMP_STAGING" == "$DUMP_TEST" ]; then
                MATCH_COUNT=$((MATCH_COUNT + 1))
            fi
        done
        
        if [ "$MATCH_COUNT" -eq 4 ]; then
            SYNC_SUCCESS="true"
        else
            SYNC_ERROR="Script executed but databases do not match completely (Matched $MATCH_COUNT/4 tables)"
        fi
    else
        SYNC_SUCCESS="false"
        SYNC_ERROR=$(cat /tmp/sql_error.log | head -n 1)
    fi
    rm -f "$TEST_DB"
fi

# 4. Create Result JSON
# Copy CSV/SQL content (truncated) for verifier analysis
CSV_CONTENT_B64=""
if [ "$CSV_EXISTS" = "true" ]; then
    CSV_CONTENT_B64=$(base64 -w 0 "$CSV_FILE")
fi

SQL_CONTENT_B64=""
if [ "$SQL_EXISTS" = "true" ]; then
    SQL_CONTENT_B64=$(base64 -w 0 "$SQL_FILE")
fi

cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_content_b64": "$CSV_CONTENT_B64",
    "sql_exists": $SQL_EXISTS,
    "sql_created_during_task": $SQL_CREATED_DURING_TASK,
    "sql_content_b64": "$SQL_CONTENT_B64",
    "conn_prod_exists": $CONN_PROD_EXISTS,
    "conn_staging_exists": $CONN_STAGING_EXISTS,
    "sync_success": $SYNC_SUCCESS,
    "sync_error": "$SYNC_ERROR"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="