#!/bin/bash
echo "=== Exporting FIFO Allocation Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Schema/Table Existence
SCHEMA_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.schemas WHERE name = 'Accounting'" | tr -d ' \r\n')
TABLE_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('Accounting.FIFOAllocation') AND type = 'U'" | tr -d ' \r\n')

# 3. Export Agent's Allocation Data
# We export the raw rows to verify logic in Python
echo "Exporting agent allocation data..."
AGENT_DATA_JSON="[]"
if [ "$TABLE_EXISTS" -gt 0 ]; then
    # Using 'FOR JSON PATH' is the cleanest way to get JSON from SQL Server
    # However, mssql-tools might truncate long output. 
    # We will use a python helper to fetch and dump if possible, or sqlcmd with specific formatting.
    # Given the environment limits, we stick to sqlcmd and basic CSV-like extraction or simple JSON construction.
    
    # Let's try to output a JSON string directly from SQL
    AGENT_DATA_JSON=$(mssql_query "
        SET NOCOUNT ON;
        SELECT 
            SalesOrderID, 
            SalesOrderDetailID, 
            BatchID, 
            QtyAllocated, 
            CAST(UnitCost AS DECIMAL(10,2)) as UnitCost
        FROM Accounting.FIFOAllocation
        ORDER BY SalesOrderID, SalesOrderDetailID, BatchID
        FOR JSON PATH;
    " "AdventureWorks2022")
    
    # Clean up the output (sqlcmd might wrap lines)
    AGENT_DATA_JSON=$(echo "$AGENT_DATA_JSON" | tr -d '\r\n')
fi

# 4. Export Source Supply Data (to reconstruct Ground Truth)
echo "Exporting supply data..."
SUPPLY_DATA_JSON=$(mssql_query "
    SET NOCOUNT ON;
    SELECT 
        BatchID, 
        Quantity, 
        CAST(UnitCost AS DECIMAL(10,2)) as UnitCost,
        CONVERT(varchar, BatchDate, 23) as BatchDate
    FROM Inventory.InputBatches
    ORDER BY BatchDate, BatchID
    FOR JSON PATH;
" "AdventureWorks2022" | tr -d '\r\n')

# 5. Export Source Demand Data (to reconstruct Ground Truth)
echo "Exporting demand data..."
DEMAND_DATA_JSON=$(mssql_query "
    SET NOCOUNT ON;
    SELECT 
        SalesOrderID, 
        SalesOrderDetailID, 
        OrderQty, 
        CONVERT(varchar, h.OrderDate, 23) as OrderDate
    FROM Sales.SalesOrderDetail d
    JOIN Sales.SalesOrderHeader h ON d.SalesOrderID = h.SalesOrderID
    WHERE d.ProductID = 707 
      AND h.OrderDate BETWEEN '2012-07-01' AND '2012-09-30'
    ORDER BY h.OrderDate, d.SalesOrderID, d.SalesOrderDetailID
    FOR JSON PATH;
" "AdventureWorks2022" | tr -d '\r\n')

# 6. Construct Final Result JSON
# Handle empty results gracefully
[ -z "$AGENT_DATA_JSON" ] && AGENT_DATA_JSON="[]"
[ -z "$SUPPLY_DATA_JSON" ] && SUPPLY_DATA_JSON="[]"
[ -z "$DEMAND_DATA_JSON" ] && DEMAND_DATA_JSON="[]"

TEMP_JSON=$(mktemp /tmp/fifo_export.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "schema_exists": $SCHEMA_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "agent_allocations": $AGENT_DATA_JSON,
    "supply_data": $SUPPLY_DATA_JSON,
    "demand_data": $DEMAND_DATA_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"