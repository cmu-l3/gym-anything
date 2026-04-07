#!/bin/bash
set -e
echo "=== Exporting inventory replenishment analysis results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

RESULT_FILE="/tmp/task_result.json"
DATABASE="AdventureWorks2022"

# 1. Check Function Existence
FN_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE name = 'fn_ProductDemandStats' AND type IN ('IF','TF')" "$DATABASE" | tr -d ' \r\n')

# 2. Check View Existence
VW_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_InventoryHealthDashboard'" "$DATABASE" | tr -d ' \r\n')

# 3. Check Table Existence
TBL_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE t.name = 'ReplenishmentQueue' AND s.name = 'Production'" "$DATABASE" | tr -d ' \r\n')

# 4. Check View Columns
# Get comma-separated list of columns
VIEW_COLUMNS=$(mssql_query "
    SELECT COLUMN_NAME 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'vw_InventoryHealthDashboard' 
    ORDER BY ORDINAL_POSITION
" "$DATABASE" | tr -d '\r' | tr '\n' ',' | sed 's/,$//')

# 5. Check View Data (Rows & Logic)
VIEW_ROW_COUNT="0"
RISK_LEVELS=""
INVALID_RISK_COUNT="0"

if [ "$VW_EXISTS" -gt 0 ]; then
    VIEW_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.vw_InventoryHealthDashboard" "$DATABASE" | tr -d ' \r\n')
    
    # Check distinct risk levels found (should contain some mix of CRITICAL, WARNING, HEALTHY)
    RISK_LEVELS=$(mssql_query "SELECT DISTINCT StockoutRiskLevel FROM dbo.vw_InventoryHealthDashboard ORDER BY StockoutRiskLevel" "$DATABASE" | tr -d '\r' | tr '\n' ',' | sed 's/,$//')
    
    # Check for any invalid risk strings
    INVALID_RISK_COUNT=$(mssql_query "
        SELECT COUNT(*) 
        FROM dbo.vw_InventoryHealthDashboard 
        WHERE StockoutRiskLevel NOT IN ('CRITICAL','WARNING','HEALTHY')
    " "$DATABASE" | tr -d ' \r\n')
fi

# 6. Check Table Data (ReplenishmentQueue)
RQ_ROW_COUNT="0"
RQ_HEALTHY_COUNT="0"
RQ_NEGATIVE_QTY="0"

if [ "$TBL_EXISTS" -gt 0 ]; then
    RQ_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.ReplenishmentQueue" "$DATABASE" | tr -d ' \r\n')
    
    # Check if 'HEALTHY' items wrongly ended up in the queue
    RQ_HEALTHY_COUNT=$(mssql_query "
        SELECT COUNT(*) 
        FROM Production.ReplenishmentQueue 
        WHERE StockoutRiskLevel = 'HEALTHY'
    " "$DATABASE" | tr -d ' \r\n')
    
    # Check for negative SuggestedOrderQty
    RQ_NEGATIVE_QTY=$(mssql_query "
        SELECT COUNT(*) 
        FROM Production.ReplenishmentQueue 
        WHERE SuggestedOrderQty < 0
    " "$DATABASE" | tr -d ' \r\n')
fi

# 7. Functional Test of the TVF
FN_TEST_ROWS="0"
if [ "$FN_EXISTS" -gt 0 ]; then
    # Call function directly to ensure it works
    FN_TEST_ROWS=$(mssql_query "SELECT COUNT(*) FROM dbo.fn_ProductDemandStats('2013-01-01', '2014-01-01')" "$DATABASE" | tr -d ' \r\n')
fi

# 8. Check timestamps (Anti-gaming)
# We can check creation_time in sys.objects relative to task start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OBJECTS_CREATED_DURING_TASK="false"

# Query to check if objects were created after task start
# SQL Server stores create_date. We'll check if create_date > task start timestamp.
# Note: SQL Server time might be UTC. Bash date +%s is UTC.
OBJ_CHECK=$(mssql_query "
    SELECT COUNT(*) 
    FROM sys.objects 
    WHERE name IN ('fn_ProductDemandStats', 'vw_InventoryHealthDashboard', 'ReplenishmentQueue')
    AND DATEDIFF(second, '1970-01-01', create_date) >= $TASK_START
" "$DATABASE" | tr -d ' \r\n')

if [ "$OBJ_CHECK" -gt 0 ]; then
    OBJECTS_CREATED_DURING_TASK="true"
fi

# Prepare JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "fn_exists": $FN_EXISTS,
    "vw_exists": $VW_EXISTS,
    "tbl_exists": $TBL_EXISTS,
    "view_columns": "$VIEW_COLUMNS",
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "risk_levels": "$RISK_LEVELS",
    "invalid_risk_count": ${INVALID_RISK_COUNT:-0},
    "rq_row_count": ${RQ_ROW_COUNT:-0},
    "rq_healthy_count": ${RQ_HEALTHY_COUNT:-0},
    "rq_negative_qty": ${RQ_NEGATIVE_QTY:-0},
    "fn_test_rows": ${FN_TEST_ROWS:-0},
    "objects_created_during_task": $OBJECTS_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="