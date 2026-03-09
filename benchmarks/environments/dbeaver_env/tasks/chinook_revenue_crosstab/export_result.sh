#!/bin/bash
# Export script for chinook_revenue_crosstab task
set -e

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Paths
DB_PATH="/home/ga/Documents/databases/chinook_crosstab.db"
CSV_PATH="/home/ga/Documents/exports/genre_yearly_revenue.csv"
SQL_PATH="/home/ga/Documents/scripts/genre_crosstab.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
DB_CONNECTION_EXISTS="false"
TABLE_EXISTS="false"
INDEX_EXISTS="false"
COLUMNS_VALID="false"
ROW_COUNT=0
TOP_GENRE_NAME=""
TOP_GENRE_TOTAL=0
TOP_GENRE_2009=0
CSV_EXISTS="false"
CSV_MATCHES_DB="false"
SQL_SCRIPT_EXISTS="false"
SQL_CONTENT_VALID="false"

# 1. Check DBeaver Connection
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -q "ChinookCrosstab" "$DBEAVER_CONFIG"; then
        DB_CONNECTION_EXISTS="true"
    fi
fi

# 2. Check Database Structure & Data (using sqlite3)
if [ -f "$DB_PATH" ]; then
    # Check Table Existence
    if sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='genre_yearly_revenue';" | grep -q "genre_yearly_revenue"; then
        TABLE_EXISTS="true"
        
        # Check Columns (exact names required by task)
        COLS=$(sqlite3 "$DB_PATH" "PRAGMA table_info(genre_yearly_revenue);" | awk -F'|' '{print $2}' | tr '\n' ',' | sed 's/,$//')
        if [[ "$COLS" == *"GenreName"* && "$COLS" == *"Rev_2009"* && "$COLS" == *"Rev_2013"* && "$COLS" == *"TotalRevenue"* ]]; then
            COLUMNS_VALID="true"
        fi

        # Get Row Count
        ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM genre_yearly_revenue;")

        # Get Top Record (for accuracy check)
        TOP_RECORD=$(sqlite3 "$DB_PATH" "SELECT GenreName, TotalRevenue, Rev_2009 FROM genre_yearly_revenue ORDER BY TotalRevenue DESC LIMIT 1;")
        TOP_GENRE_NAME=$(echo "$TOP_RECORD" | awk -F'|' '{print $1}')
        TOP_GENRE_TOTAL=$(echo "$TOP_RECORD" | awk -F'|' '{print $2}')
        TOP_GENRE_2009=$(echo "$TOP_RECORD" | awk -F'|' '{print $3}')
    fi

    # Check Index Existence
    if sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_genre_total_revenue';" | grep -q "idx_genre_total_revenue"; then
        INDEX_EXISTS="true"
    fi
fi

# 3. Check CSV Export
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Basic validation: check if CSV row count roughly matches DB row count (+1 for header)
    CSV_LINES=$(wc -l < "$CSV_PATH")
    DB_LINES=$((ROW_COUNT + 1))
    if [ "$CSV_LINES" -ge "$ROW_COUNT" ] && [ "$ROW_COUNT" -gt 0 ]; then
        CSV_MATCHES_DB="true"
    fi
fi

# 4. Check SQL Script
if [ -f "$SQL_PATH" ]; then
    SQL_SCRIPT_EXISTS="true"
    CONTENT=$(cat "$SQL_PATH" | tr '[:upper:]' '[:lower:]')
    if [[ "$CONTENT" == *"create table"* && "$CONTENT" == *"case when"* && "$CONTENT" == *"create index"* ]]; then
        SQL_CONTENT_VALID="true"
    fi
fi

# Load ground truth for reference in JSON
GT_JSON=$(cat /tmp/ground_truth_values.json 2>/dev/null || echo "[{}]")
GT_GENRE_COUNT=$(cat /tmp/ground_truth_genre_count.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Create JSON result
cat <<EOF > /tmp/task_result.json
{
    "db_connection_exists": $DB_CONNECTION_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "index_exists": $INDEX_EXISTS,
    "columns_valid": $COLUMNS_VALID,
    "row_count": $ROW_COUNT,
    "top_genre_name": "$TOP_GENRE_NAME",
    "top_genre_total": "${TOP_GENRE_TOTAL:-0}",
    "top_genre_2009": "${TOP_GENRE_2009:-0}",
    "csv_exists": $CSV_EXISTS,
    "csv_matches_db": $CSV_MATCHES_DB,
    "sql_script_exists": $SQL_SCRIPT_EXISTS,
    "sql_content_valid": $SQL_CONTENT_VALID,
    "ground_truth_json": $GT_JSON,
    "ground_truth_genre_count": $GT_GENRE_COUNT,
    "task_start_time": $TASK_START_TIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Handle permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"