#!/bin/bash
# Export results for sales_trend_quarterly_analysis task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || true

MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

ADS_RUNNING="false"
if ads_is_running; then ADS_RUNNING="true"; fi

# ── Check: View exists ────────────────────────────────────────────────────────
VIEW_EXISTS="false"
VIEW_ROW_COUNT=0
COLUMNS_FOUND=""
HAS_REQUIRED_COLUMNS="false"
REQUIRED_COLUMN_COUNT=0
LAG_WORKS="false"
RANK_STARTS_AT_1="false"

if [ "$MSSQL_RUNNING" = "true" ]; then
    VC=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_SalesPersonQuarterlyTrend' AND schema_id = SCHEMA_ID('dbo')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${VC:-0}" -gt 0 ] 2>/dev/null && VIEW_EXISTS="true"

    if [ "$VIEW_EXISTS" = "true" ]; then
        # Get column list
        COLUMNS_FOUND=$(mssql_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'vw_SalesPersonQuarterlyTrend' AND TABLE_SCHEMA = 'dbo'
            ORDER BY ORDINAL_POSITION
        " "AdventureWorks2022" | tr -d '\r' | grep -v '^$' | tr '\n' ',')

        # Check required columns (at least 8 of 10 for full credit)
        REQUIRED_COLS=("SalesPersonID" "FirstName" "LastName" "TerritoryName" "CalendarYear" "CalendarQuarter" "QuarterlySales" "PrevQuarterSales" "QoQGrowthPct" "SalesRankInTerritory")
        REQUIRED_COLUMN_COUNT=0
        cols_lower=$(echo "$COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
        for col in "${REQUIRED_COLS[@]}"; do
            col_lower=$(echo "$col" | tr '[:upper:]' '[:lower:]')
            if echo "$cols_lower" | grep -qiE "(^|,)${col_lower}(,|$)"; then
                REQUIRED_COLUMN_COUNT=$((REQUIRED_COLUMN_COUNT + 1))
            fi
        done
        [ "$REQUIRED_COLUMN_COUNT" -ge 8 ] && HAS_REQUIRED_COLUMNS="true"

        # Row count
        VIEW_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.vw_SalesPersonQuarterlyTrend" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        VIEW_ROW_COUNT=${VIEW_ROW_COUNT:-0}

        # Check if LAG is working: PrevQuarterSales should have some non-zero values
        if echo "$cols_lower" | grep -q "prevquartersales"; then
            LAG_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.vw_SalesPersonQuarterlyTrend WHERE PrevQuarterSales > 0" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
            [ "${LAG_COUNT:-0}" -gt 0 ] 2>/dev/null && LAG_WORKS="true"
        fi

        # Check if SalesRankInTerritory starts at 1
        if echo "$cols_lower" | grep -q "salesrankinterritory"; then
            RANK_MIN=$(mssql_query "SELECT MIN(SalesRankInTerritory) FROM dbo.vw_SalesPersonQuarterlyTrend" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
            [ "${RANK_MIN:-99}" = "1" ] 2>/dev/null && RANK_STARTS_AT_1="true"
        fi
    fi
fi

# ── Check: CSV file exists and is valid ───────────────────────────────────────
CSV_PATH="/home/ga/Documents/exports/top_sales_trends.csv"
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_HAS_HEADER="false"
CSV_HEADER=""
CSV_FIRST_NAMES=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Count data rows (total lines - 1 for header)
    TOTAL_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null; true)
    CSV_ROW_COUNT=$(( ${TOTAL_LINES:-1} - 1 ))
    [ "$CSV_ROW_COUNT" -lt 0 ] && CSV_ROW_COUNT=0

    # Get header row
    CSV_HEADER=$(head -1 "$CSV_PATH" 2>/dev/null | tr '[:upper:]' '[:lower:]')

    # Check header has expected columns
    if echo "$CSV_HEADER" | grep -qi "first\|last\|name\|sales"; then
        CSV_HAS_HEADER="true"
    fi

    # Get salesperson names from CSV for cross-validation
    CSV_FIRST_NAMES=$(tail -n +2 "$CSV_PATH" 2>/dev/null | awk -F',' '{print $2}' | tr -d '"' | tr -d '\r' | grep -v '^$' | head -5 | tr '\n' ',')
fi

# ── Cross-validate CSV against database ───────────────────────────────────────
CSV_DB_MATCH_COUNT=0

if [ "$CSV_EXISTS" = "true" ] && [ "$MSSQL_RUNNING" = "true" ] && [ "$VIEW_EXISTS" = "true" ]; then
    # Get top 5 FirstNames from the DB query (the expected answer)
    DB_TOP5=$(mssql_query "
        SELECT TOP 5 FirstName
        FROM dbo.vw_SalesPersonQuarterlyTrend
        WHERE PrevQuarterSales > 0 AND QoQGrowthPct IS NOT NULL
        GROUP BY SalesPersonID, FirstName, LastName, TerritoryName
        ORDER BY AVG(ISNULL(QoQGrowthPct, 0)) DESC
    " "AdventureWorks2022" 2>/dev/null | tr -d '\r' | grep -v '^$' | head -5)

    if [ -n "$DB_TOP5" ] && [ -n "$CSV_FIRST_NAMES" ]; then
        while IFS= read -r fname; do
            fname_clean=$(echo "$fname" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
            if echo "$CSV_FIRST_NAMES" | tr '[:upper:]' '[:lower:]' | tr -d ' ' | grep -q "$fname_clean"; then
                CSV_DB_MATCH_COUNT=$((CSV_DB_MATCH_COUNT + 1))
            fi
        done <<< "$DB_TOP5"
    fi
fi

# Build JSON result
cat > /tmp/sales_trend_result.json << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "view_exists": $VIEW_EXISTS,
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "has_required_columns": $HAS_REQUIRED_COLUMNS,
    "required_column_count": $REQUIRED_COLUMN_COUNT,
    "columns_found": "$COLUMNS_FOUND",
    "lag_works": $LAG_WORKS,
    "rank_starts_at_1": $RANK_STARTS_AT_1,
    "csv_exists": $CSV_EXISTS,
    "csv_row_count": ${CSV_ROW_COUNT:-0},
    "csv_has_header": $CSV_HAS_HEADER,
    "csv_header": "$CSV_HEADER",
    "csv_first_names": "$CSV_FIRST_NAMES",
    "csv_db_match_count": $CSV_DB_MATCH_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/sales_trend_result.json 2>/dev/null || true
echo "Result saved to /tmp/sales_trend_result.json"
cat /tmp/sales_trend_result.json
echo ""
echo "=== Export complete ==="
exit 0
