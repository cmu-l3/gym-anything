#!/bin/bash
# Export script for chinook_northwind_market_overlap task
echo "=== Exporting Market Overlap Result ==="

source /workspace/scripts/task_utils.sh

# Paths
ANALYSIS_DB="/home/ga/Documents/databases/market_analysis.db"
CSV_REPORT="/home/ga/Documents/exports/market_overlap_report.csv"
SQL_SCRIPT="/home/ga/Documents/scripts/market_analysis.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo 0)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check DBeaver Connections
echo "Checking DBeaver connections..."
CHINOOK_CONN="false"
NORTHWIND_CONN="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Simple grep check for connection names
    if grep -q '"name": "Chinook"' "$DBEAVER_CONFIG"; then CHINOOK_CONN="true"; fi
    if grep -q '"name": "Northwind"' "$DBEAVER_CONFIG"; then NORTHWIND_CONN="true"; fi
fi

# 3. Analyze the User's Created Database (market_analysis.db)
DB_EXISTS="false"
TBL_CHINOOK_STATS="false"
TBL_NORTHWIND_STATS="false"
TBL_OVERLAP="false"
OVERLAP_ROWS=0
TOP_COUNTRY=""
TOP_REVENUE=0
HAS_UK_NORMALIZATION="false"

if [ -f "$ANALYSIS_DB" ]; then
    DB_EXISTS="true"
    
    # Check Tables
    TABLES=$(sqlite3 "$ANALYSIS_DB" "SELECT name FROM sqlite_master WHERE type='table';")
    if echo "$TABLES" | grep -q "chinook_country_stats"; then TBL_CHINOOK_STATS="true"; fi
    if echo "$TABLES" | grep -q "northwind_country_stats"; then TBL_NORTHWIND_STATS="true"; fi
    if echo "$TABLES" | grep -q "market_overlap"; then TBL_OVERLAP="true"; fi
    
    # Check Overlap Data
    if [ "$TBL_OVERLAP" = "true" ]; then
        OVERLAP_ROWS=$(sqlite3 "$ANALYSIS_DB" "SELECT COUNT(*) FROM market_overlap;" 2>/dev/null || echo 0)
        
        # Get top country by combined revenue
        TOP_INFO=$(sqlite3 "$ANALYSIS_DB" "SELECT Country, CombinedRevenue FROM market_overlap ORDER BY CombinedRevenue DESC LIMIT 1;" 2>/dev/null)
        TOP_COUNTRY=$(echo "$TOP_INFO" | cut -d'|' -f1)
        TOP_REVENUE=$(echo "$TOP_INFO" | cut -d'|' -f2)

        # Check for normalization (Does the overlap table contain US/USA and UK/United Kingdom?)
        # Ideally, we see United Kingdom OR UK, but not just one side unmatched.
        # We'll check if 'United Kingdom' or 'UK' exists in the overlap table, implying a match was found.
        if sqlite3 "$ANALYSIS_DB" "SELECT Country FROM market_overlap;" | grep -Eiq "^(UK|United Kingdom)$"; then
            HAS_UK_NORMALIZATION="true"
        fi
    fi
fi

# 4. Analyze CSV Export
CSV_EXISTS="false"
CSV_ROWS=0
CSV_COLS=0
CSV_CREATED_DURING="false"

if [ -f "$CSV_REPORT" ]; then
    CSV_EXISTS="true"
    CSV_ROWS=$(count_csv_lines "$CSV_REPORT") # Uses helper from task_utils.sh
    CSV_COLS=$(count_csv_columns "$CSV_REPORT")
    
    FILE_TIME=$(stat -c%Y "$CSV_REPORT" 2>/dev/null)
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
fi

# 5. Check SQL Script
SQL_EXISTS="false"
SQL_SIZE=0
if [ -f "$SQL_SCRIPT" ]; then
    SQL_EXISTS="true"
    SQL_SIZE=$(stat -c%s "$SQL_SCRIPT" 2>/dev/null)
fi

# 6. Generate JSON Result
cat > /tmp/task_result.json << EOF
{
    "connections": {
        "chinook": $CHINOOK_CONN,
        "northwind": $NORTHWIND_CONN
    },
    "database": {
        "exists": $DB_EXISTS,
        "tables": {
            "chinook_stats": $TBL_CHINOOK_STATS,
            "northwind_stats": $TBL_NORTHWIND_STATS,
            "overlap": $TBL_OVERLAP
        },
        "overlap_row_count": $OVERLAP_ROWS,
        "top_country": "$TOP_COUNTRY",
        "top_revenue": "${TOP_REVENUE:-0}",
        "uk_normalization_detected": $HAS_UK_NORMALIZATION
    },
    "csv": {
        "exists": $CSV_EXISTS,
        "rows": $CSV_ROWS,
        "cols": $CSV_COLS,
        "created_during_task": $CSV_CREATED_DURING
    },
    "sql_script": {
        "exists": $SQL_EXISTS,
        "size": $SQL_SIZE
    },
    "timestamp": $(date +%s)
}
EOF

# Safe copy to allow verify script to read it
chmod 644 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="