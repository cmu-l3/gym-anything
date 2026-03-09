#!/bin/bash
# Export script for chinook_regional_market_mapping
# Verifies database state and exports results

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
CSV_PATH="/home/ga/Documents/exports/regional_sales_summary.csv"
SQL_PATH="/home/ga/Documents/scripts/create_regions.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Files
CSV_EXISTS="false"
CSV_MODIFIED="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Check modification time
    FMOD=$(stat -c %Y "$CSV_PATH")
    if [ "$FMOD" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
fi

SQL_EXISTS="false"
if [ -f "$SQL_PATH" ]; then
    SQL_EXISTS="true"
fi

# 2. Check Database Objects & Schema
TABLE_EXISTS="false"
VIEW_EXISTS="false"
MAPPING_COUNT=0
USA_REGION=""
BRAZIL_REGION=""
GERMANY_REGION=""
INDIA_REGION=""
OTHER_CHECK=""

if [ -f "$CHINOOK_DB" ]; then
    # Check table existence
    if sqlite3 "$CHINOOK_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='region_mapping';" | grep -q "region_mapping"; then
        TABLE_EXISTS="true"
        
        # Check mapping count
        MAPPING_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM region_mapping;" 2>/dev/null || echo 0)
        
        # Spot check specific mappings
        USA_REGION=$(sqlite3 "$CHINOOK_DB" "SELECT RegionCode FROM region_mapping WHERE Country='USA';" 2>/dev/null || echo "")
        BRAZIL_REGION=$(sqlite3 "$CHINOOK_DB" "SELECT RegionCode FROM region_mapping WHERE Country='Brazil';" 2>/dev/null || echo "")
        GERMANY_REGION=$(sqlite3 "$CHINOOK_DB" "SELECT RegionCode FROM region_mapping WHERE Country='Germany';" 2>/dev/null || echo "")
        INDIA_REGION=$(sqlite3 "$CHINOOK_DB" "SELECT RegionCode FROM region_mapping WHERE Country='India';" 2>/dev/null || echo "")
        
        # Check for 'Other' logic (if any countries fall outside the list)
        # We query for a country NOT in the main list if one exists, or check code 'OTH' existence
        OTHER_CHECK=$(sqlite3 "$CHINOOK_DB" "SELECT COUNT(*) FROM region_mapping WHERE RegionCode='OTH';" 2>/dev/null || echo 0)
    fi

    # Check view existence
    if sqlite3 "$CHINOOK_DB" "SELECT name FROM sqlite_master WHERE type='view' AND name='v_regional_sales';" | grep -q "v_regional_sales"; then
        VIEW_EXISTS="true"
    fi
fi

# 3. Check View Data (Aggregations)
# We run the user's view and capture the output to verify logic
VIEW_RESULTS_JSON="{}"
if [ "$VIEW_EXISTS" = "true" ]; then
    VIEW_RESULTS_JSON=$(python3 -c "
import sqlite3, json
try:
    conn = sqlite3.connect('$CHINOOK_DB')
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM v_regional_sales')
    cols = [d[0] for d in cursor.description]
    rows = cursor.fetchall()
    data = []
    for row in rows:
        data.append(dict(zip(cols, row)))
    print(json.dumps(data))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)
fi

# 4. Check DBeaver Connection
DBEAVER_CONN_FOUND="false"
CONFIG_FILE="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$CONFIG_FILE" ]; then
    if grep -q "Chinook" "$CONFIG_FILE"; then
        DBEAVER_CONN_FOUND="true"
    fi
fi

# 5. Capture Screenshot
take_screenshot /tmp/task_final.png

# 6. Read Ground Truth
GROUND_TRUTH="{}"
if [ -f "/tmp/region_ground_truth.json" ]; then
    GROUND_TRUTH=$(cat /tmp/region_ground_truth.json)
fi

# 7. Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED,
    "sql_exists": $SQL_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "view_exists": $VIEW_EXISTS,
    "mapping_count": $MAPPING_COUNT,
    "mappings": {
        "USA": "$USA_REGION",
        "Brazil": "$BRAZIL_REGION",
        "Germany": "$GERMANY_REGION",
        "India": "$INDIA_REGION"
    },
    "other_count": $OTHER_CHECK,
    "view_data": $VIEW_RESULTS_JSON,
    "ground_truth": $GROUND_TRUTH,
    "dbeaver_connection": $DBEAVER_CONN_FOUND
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="