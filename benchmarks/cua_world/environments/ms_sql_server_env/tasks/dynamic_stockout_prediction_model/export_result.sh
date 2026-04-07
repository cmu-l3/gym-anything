#!/bin/bash
# Export results for dynamic_stockout_prediction_model task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check SQL Server running
MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

# ── Check 1: View Existence & Schema ──────────────────────────────────────────
VIEW_EXISTS="false"
VIEW_COLUMNS=""
HAS_REQUIRED_COLS="false"

if [ "$MSSQL_RUNNING" = "true" ]; then
    VC=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_ProductStockoutProjection' AND schema_id = SCHEMA_ID('Production')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${VC:-0}" -gt 0 ] 2>/dev/null && VIEW_EXISTS="true"

    if [ "$VIEW_EXISTS" = "true" ]; then
        VIEW_COLUMNS=$(mssql_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'Production' AND TABLE_NAME = 'vw_ProductStockoutProjection'
        " "AdventureWorks2022" | tr -d '\r' | tr '\n' ',')
        
        # Check required columns
        REQUIRED="CurrentInventory,TotalSales2013,AvgDailyBurnRate,EstimatedDaysSupply,ProjectedStockoutDate"
        MISSING=0
        for col in $(echo $REQUIRED | tr ',' ' '); do
            if ! echo "$VIEW_COLUMNS" | grep -qi "$col"; then
                MISSING=1
            fi
        done
        [ "$MISSING" -eq 0 ] && HAS_REQUIRED_COLS="true"
    fi
fi

# ── Check 2: Logic Verification (Spot Check Product 707) ──────────────────────
# Product 707 (Sport-100 Helmet, Red)
# We calculate Ground Truth values using raw queries
GT_INVENTORY=0
GT_SALES_2013=0
GT_BURN_RATE=0
GT_DAYS_SUPPLY=0
GT_STOCKOUT_DATE=""

VIEW_INVENTORY=0
VIEW_SALES_2013=0
VIEW_BURN_RATE=0
VIEW_STOCKOUT_DATE=""

if [ "$VIEW_EXISTS" = "true" ]; then
    # Ground Truth Calculation
    GT_INVENTORY=$(mssql_query "SELECT ISNULL(SUM(Quantity),0) FROM Production.ProductInventory WHERE ProductID = 707" "AdventureWorks2022" | tr -d ' \r\n')
    
    GT_SALES_2013=$(mssql_query "
        SELECT ISNULL(SUM(OrderQty),0) 
        FROM Sales.SalesOrderDetail sod 
        JOIN Sales.SalesOrderHeader soh ON sod.SalesOrderID = soh.SalesOrderID 
        WHERE sod.ProductID = 707 AND soh.OrderDate >= '2013-01-01' AND soh.OrderDate < '2014-01-01'
    " "AdventureWorks2022" | tr -d ' \r\n')
    
    # Calculate derived GT values in Python to handle float precision easily
    GT_JSON=$(python3 -c "
import datetime
inv = float($GT_INVENTORY)
sales = float($GT_SALES_2013)
burn = sales / 365.0
if burn > 0:
    days = inv / burn
    # Anchor date 2014-01-01
    anchor = datetime.date(2014, 1, 1)
    # Add floor(days)
    proj = anchor + datetime.timedelta(days=int(days))
    date_str = proj.strftime('%Y-%m-%d')
else:
    days = 0
    date_str = 'NULL'

print(f'{burn}|{days}|{date_str}')
")
    
    GT_BURN_RATE=$(echo "$GT_JSON" | cut -d'|' -f1)
    GT_STOCKOUT_DATE=$(echo "$GT_JSON" | cut -d'|' -f3)

    # Get Agent's View Values for Product 707
    AGENT_VALS=$(mssql_query "
        SELECT 
            CurrentInventory, 
            TotalSales2013, 
            CAST(AvgDailyBurnRate AS FLOAT), 
            FORMAT(ProjectedStockoutDate, 'yyyy-MM-dd')
        FROM Production.vw_ProductStockoutProjection 
        WHERE ProductID = 707
    " "AdventureWorks2022" | sed -n '3p' | tr -d '\r')
    
    # Parse Agent Values (handling potential whitespace/formatting)
    # Expected format from sqlcmd -W: val1 val2 val3 val4
    # We'll assume space separated.
    VIEW_INVENTORY=$(echo "$AGENT_VALS" | awk '{print $1}')
    VIEW_SALES_2013=$(echo "$AGENT_VALS" | awk '{print $2}')
    VIEW_BURN_RATE=$(echo "$AGENT_VALS" | awk '{print $3}')
    VIEW_STOCKOUT_DATE=$(echo "$AGENT_VALS" | awk '{print $4}')
fi

# ── Check 3: Stored Procedure Existence & Functionality ───────────────────────
PROC_EXISTS="false"
PROC_WORKS="false"

if [ "$MSSQL_RUNNING" = "true" ]; then
    PC=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_GetCriticalStockouts' AND schema_id = SCHEMA_ID('Production')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${PC:-0}" -gt 0 ] 2>/dev/null && PROC_EXISTS="true"

    # Test execution
    if [ "$PROC_EXISTS" = "true" ]; then
        TEST_ROWS=$(mssql_query "EXEC Production.usp_GetCriticalStockouts @RunwayDays = 10" "AdventureWorks2022" | wc -l)
        [ "$TEST_ROWS" -gt 2 ] && PROC_WORKS="true"
    fi
fi

# ── Check 4: CSV Export ───────────────────────────────────────────────────────
CSV_PATH="/home/ga/Documents/critical_stockouts.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_HEADER_MATCH="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_ROWS=$(wc -l < "$CSV_PATH")
    HEADER=$(head -n 1 "$CSV_PATH" | tr '[:upper:]' '[:lower:]')
    if echo "$HEADER" | grep -q "productid" && echo "$HEADER" | grep -q "stockoutdate"; then
        CSV_HEADER_MATCH="true"
    fi
fi

# ── Build JSON Result ─────────────────────────────────────────────────────────
cat > /tmp/result_data.json << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "view_exists": $VIEW_EXISTS,
    "has_required_cols": $HAS_REQUIRED_COLS,
    "proc_exists": $PROC_EXISTS,
    "proc_works": $PROC_WORKS,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_header_match": $CSV_HEADER_MATCH,
    "spot_check": {
        "product_id": 707,
        "gt_inventory": "$GT_INVENTORY",
        "gt_sales": "$GT_SALES_2013",
        "gt_burn_rate": "$GT_BURN_RATE",
        "gt_date": "$GT_STOCKOUT_DATE",
        "view_inventory": "$VIEW_INVENTORY",
        "view_sales": "$VIEW_SALES_2013",
        "view_burn_rate": "$VIEW_BURN_RATE",
        "view_date": "$VIEW_STOCKOUT_DATE"
    }
}
EOF

# Safe move
mv /tmp/result_data.json /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json