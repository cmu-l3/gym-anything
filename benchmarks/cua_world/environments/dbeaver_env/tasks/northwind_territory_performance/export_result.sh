#!/bin/bash
# Export script for northwind_territory_performance task

echo "=== Exporting Northwind Territory Performance Result ==="

source /workspace/scripts/task_utils.sh

EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
TERRITORY_CSV="$EXPORT_DIR/territory_report.csv"
TERRITORY_SQL="$SCRIPTS_DIR/territory_analysis.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Take final screenshot
take_screenshot /tmp/northwind_task_end.png
sleep 1

# Check DBeaver connection
NORTHWIND_CONN_FOUND="false"
NORTHWIND_CONN_PATH=""
if [ -f "$DBEAVER_CONFIG" ]; then
    CONN_CHECK=$(python3 -c "
import json, sys
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    for k, v in config.get('connections', {}).items():
        name = v.get('name', '')
        if name.lower() == 'northwind':
            db_path = v.get('configuration', {}).get('database', '')
            print(f'found|{db_path}')
            sys.exit(0)
    print('not_found|')
except Exception as e:
    print(f'error|{e}')
" 2>/dev/null)
    if echo "$CONN_CHECK" | grep -q "^found|"; then
        NORTHWIND_CONN_FOUND="true"
        NORTHWIND_CONN_PATH=$(echo "$CONN_CHECK" | cut -d'|' -f2)
    fi
fi

# Check output CSV
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_COLUMN_COUNT=0
CSV_HAS_TERRITORY_ID="false"
CSV_HAS_REVENUE="false"
CSV_HAS_REGION="false"
CSV_TOP_REVENUE=0
CSV_FIRST_ROW=""

if [ -f "$TERRITORY_CSV" ]; then
    CSV_EXISTS="true"
    CSV_ROW_COUNT=$(count_csv_lines "$TERRITORY_CSV")
    CSV_COLUMN_COUNT=$(count_csv_columns "$TERRITORY_CSV")

    HEADER=$(head -1 "$TERRITORY_CSV" | tr '[:upper:]' '[:lower:]')
    echo "$HEADER" | grep -qi "territoryid\|territory_id" && CSV_HAS_TERRITORY_ID="true"
    echo "$HEADER" | grep -qi "totalrevenue\|total_revenue\|revenue" && CSV_HAS_REVENUE="true"
    echo "$HEADER" | grep -qi "regiondescription\|region" && CSV_HAS_REGION="true"

    # Extract top revenue from first data row (assuming sorted by revenue desc)
    CSV_FIRST_ROW=$(sed -n '2p' "$TERRITORY_CSV")
    CSV_TOP_REVENUE=$(python3 -c "
import csv, sys
try:
    with open('$TERRITORY_CSV') as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        # Find revenue column (case-insensitive)
        rev_col = next((h for h in headers if 'revenue' in h.lower()), None)
        if rev_col:
            for row in reader:
                val = row[rev_col].replace(',','').replace('\$','').strip()
                try:
                    print(round(float(val), 2))
                    break
                except:
                    pass
        print(0)
except:
    print(0)
" 2>/dev/null || echo 0)
fi

# Check SQL script file
SQL_EXISTS="false"
SQL_FILE_SIZE=0
if [ -f "$TERRITORY_SQL" ]; then
    SQL_EXISTS="true"
    SQL_FILE_SIZE=$(get_file_size "$TERRITORY_SQL")
fi

# Also check DBeaver scripts folder
DBEAVER_SCRIPTS_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/Scripts"
DBEAVER_SQL_EXISTS="false"
if find "$DBEAVER_SCRIPTS_DIR" -name "*.sql" 2>/dev/null | grep -qi "territory"; then
    DBEAVER_SQL_EXISTS="true"
fi

# Read ground truth
GT_TOP_REVENUE=0
GT_TERRITORY_COUNT=0
GT_TOP_TERRITORY_ID=""
if [ -f /tmp/northwind_territory_gt.json ]; then
    GT_TOP_REVENUE=$(python3 -c "import json; d=json.load(open('/tmp/northwind_territory_gt.json')); print(d.get('top_territory_revenue', 0))" 2>/dev/null || echo 0)
    GT_TERRITORY_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/northwind_territory_gt.json')); print(d.get('territory_count', 0))" 2>/dev/null || echo 0)
    GT_TOP_TERRITORY_ID=$(python3 -c "import json; d=json.load(open('/tmp/northwind_territory_gt.json')); print(d.get('top_territory_id', ''))" 2>/dev/null || echo "")
fi

INITIAL_CONN_COUNT=$(cat /tmp/initial_dbeaver_conn_count 2>/dev/null || echo 0)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)
CSV_CREATED_AFTER_START="false"
if [ -f "$TERRITORY_CSV" ]; then
    FILE_TIME=$(stat -c%Y "$TERRITORY_CSV" 2>/dev/null || stat -f%m "$TERRITORY_CSV" 2>/dev/null || echo 0)
    [ "$FILE_TIME" -gt "$TASK_START" ] && CSV_CREATED_AFTER_START="true"
fi

# Build result JSON
cat > /tmp/northwind_territory_result.json << EOF
{
    "northwind_conn_found": $NORTHWIND_CONN_FOUND,
    "northwind_conn_path": "$NORTHWIND_CONN_PATH",
    "csv_exists": $CSV_EXISTS,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_column_count": $CSV_COLUMN_COUNT,
    "csv_has_territory_id": $CSV_HAS_TERRITORY_ID,
    "csv_has_revenue": $CSV_HAS_REVENUE,
    "csv_has_region": $CSV_HAS_REGION,
    "csv_top_revenue": $CSV_TOP_REVENUE,
    "csv_created_after_start": $CSV_CREATED_AFTER_START,
    "sql_script_exists": $SQL_EXISTS,
    "sql_script_size": $SQL_FILE_SIZE,
    "dbeaver_sql_in_scripts": $DBEAVER_SQL_EXISTS,
    "gt_top_revenue": $GT_TOP_REVENUE,
    "gt_territory_count": $GT_TERRITORY_COUNT,
    "gt_top_territory_id": "$GT_TOP_TERRITORY_ID",
    "initial_conn_count": $INITIAL_CONN_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/northwind_territory_result.json
echo ""
echo "=== Export Complete ==="
