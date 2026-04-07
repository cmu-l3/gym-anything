#!/bin/bash
# Export results for wac_inventory_ledger task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || true

MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

ADS_RUNNING="false"
if ads_is_running; then ADS_RUNNING="true"; fi

# ── Check: Stored procedure exists ────────────────────────────────────────────
PROC_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    PC=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_BuildWACLedger' AND schema_id = SCHEMA_ID('Production')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${PC:-0}" -gt 0 ] 2>/dev/null && PROC_EXISTS="true"
fi

# ── Check: Production.InventoryLedger table ───────────────────────────────────
TABLE_EXISTS="false"
TABLE_ROW_COUNT=0
COLUMNS_FOUND=""
HAS_REQUIRED_COLUMNS="false"
REQUIRED_COLUMN_COUNT=0
DISTINCT_PRODUCTS=0
NEGATIVE_QTY_COUNT=-1
ZERO_QTY_NONZERO_WAC=-1

if [ "$MSSQL_RUNNING" = "true" ]; then
    TC=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('Production.InventoryLedger') AND type = 'U'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${TC:-0}" -gt 0 ] 2>/dev/null && TABLE_EXISTS="true"

    if [ "$TABLE_EXISTS" = "true" ]; then
        # Get columns
        COLUMNS_FOUND=$(mssql_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'Production' AND TABLE_NAME = 'InventoryLedger'
            ORDER BY ORDINAL_POSITION
        " "AdventureWorks2022" | tr -d '\r' | grep -v '^$' | tr '\n' ',')

        # Check required columns
        REQUIRED_COLS=("TransactionID" "ProductID" "TransactionDate" "TransactionType" "Qty" "UnitCost" "RunningQty" "RunningWAC" "RunningTotalValue")
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
        TABLE_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.InventoryLedger" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        TABLE_ROW_COUNT=${TABLE_ROW_COUNT:-0}

        # Distinct products
        DISTINCT_PRODUCTS=$(mssql_query "SELECT COUNT(DISTINCT ProductID) FROM Production.InventoryLedger" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        DISTINCT_PRODUCTS=${DISTINCT_PRODUCTS:-0}

        # Critical check: no negative RunningQty
        if echo "$cols_lower" | grep -q "runningqty"; then
            NEGATIVE_QTY_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.InventoryLedger WHERE RunningQty < 0" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
            NEGATIVE_QTY_COUNT=${NEGATIVE_QTY_COUNT:-(-1)}
        fi

        # Critical check: WAC resets to 0 when qty is 0
        if echo "$cols_lower" | grep -q "runningwac"; then
            ZERO_QTY_NONZERO_WAC=$(mssql_query "SELECT COUNT(*) FROM Production.InventoryLedger WHERE RunningQty = 0 AND RunningWAC != 0" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
            ZERO_QTY_NONZERO_WAC=${ZERO_QTY_NONZERO_WAC:-(-1)}
        fi
    fi
fi

# ── Check: Production.vw_CostVarianceReport view ─────────────────────────────
VIEW_EXISTS="false"
VIEW_ROW_COUNT=0
INVESTIGATE_COUNT=0
VIEW_COLUMNS_FOUND=""
VIEW_HAS_REQUIRED_COLUMNS="false"
VIEW_REQUIRED_COLUMN_COUNT=0

if [ "$MSSQL_RUNNING" = "true" ]; then
    VC=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_CostVarianceReport' AND schema_id = SCHEMA_ID('Production')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${VC:-0}" -gt 0 ] 2>/dev/null && VIEW_EXISTS="true"

    if [ "$VIEW_EXISTS" = "true" ]; then
        VIEW_COLUMNS_FOUND=$(mssql_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'Production' AND TABLE_NAME = 'vw_CostVarianceReport'
            ORDER BY ORDINAL_POSITION
        " "AdventureWorks2022" | tr -d '\r' | grep -v '^$' | tr '\n' ',')

        VIEW_REQUIRED_COLS=("ProductID" "ProductName" "FinalWAC" "StandardCost" "VariancePct" "Flag")
        VIEW_REQUIRED_COLUMN_COUNT=0
        vcols_lower=$(echo "$VIEW_COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
        for col in "${VIEW_REQUIRED_COLS[@]}"; do
            col_lower=$(echo "$col" | tr '[:upper:]' '[:lower:]')
            if echo "$vcols_lower" | grep -qiE "(^|,)${col_lower}(,|$)"; then
                VIEW_REQUIRED_COLUMN_COUNT=$((VIEW_REQUIRED_COLUMN_COUNT + 1))
            fi
        done
        [ "$VIEW_REQUIRED_COLUMN_COUNT" -ge 5 ] && VIEW_HAS_REQUIRED_COLUMNS="true"

        VIEW_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.vw_CostVarianceReport" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        VIEW_ROW_COUNT=${VIEW_ROW_COUNT:-0}

        INVESTIGATE_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.vw_CostVarianceReport WHERE Flag = 'INVESTIGATE'" "AdventureWorks2022" 2>/dev/null | tr -d ' \r\n'; true)
        INVESTIGATE_COUNT=${INVESTIGATE_COUNT:-0}
    fi
fi

# ── Check: CSV file ──────────────────────────────────────────────────────────
CSV_EXISTS="false"
CSV_ROWS=0
CSV_HEADER=""
CSV_SIZE=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_CREATED_DURING_TASK="false"

CSV_PATH="/home/ga/Documents/exports/cost_variance.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_ROWS=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_HEADER=$(head -1 "$CSV_PATH" 2>/dev/null || echo "")
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# ── Build JSON result ─────────────────────────────────────────────────────────
cat > /tmp/wac_result.json << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "proc_exists": $PROC_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "table_row_count": ${TABLE_ROW_COUNT:-0},
    "columns_found": "$COLUMNS_FOUND",
    "has_required_columns": $HAS_REQUIRED_COLUMNS,
    "required_column_count": $REQUIRED_COLUMN_COUNT,
    "distinct_products": ${DISTINCT_PRODUCTS:-0},
    "negative_qty_count": ${NEGATIVE_QTY_COUNT:--1},
    "zero_qty_nonzero_wac": ${ZERO_QTY_NONZERO_WAC:--1},
    "view_exists": $VIEW_EXISTS,
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "view_columns_found": "$VIEW_COLUMNS_FOUND",
    "view_has_required_columns": $VIEW_HAS_REQUIRED_COLUMNS,
    "view_required_column_count": $VIEW_REQUIRED_COLUMN_COUNT,
    "investigate_count": ${INVESTIGATE_COUNT:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_header": "$CSV_HEADER",
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/wac_result.json 2>/dev/null || true
echo "Result saved to /tmp/wac_result.json"
cat /tmp/wac_result.json
echo ""
echo "=== Export complete ==="
exit 0
