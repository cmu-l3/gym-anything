#!/bin/bash
# Export script for reseller_order_sessionization task
echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check for Object Existence (Schema, Table, Proc, Index)
echo "Checking database objects..."
OBJECT_CHECK_JSON=$(mssql_query "
    SELECT 
        (SELECT COUNT(*) FROM sys.schemas WHERE name = 'Logistics') as schema_exists,
        (SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('Logistics.ResellerRestockingSessions') AND type = 'U') as table_exists,
        (SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_GenerateRestockingSessions' AND schema_id = SCHEMA_ID('Logistics')) as proc_exists,
        (SELECT COUNT(*) FROM sys.indexes WHERE name = 'IX_ResellerSessions_CustomerID' AND object_id = OBJECT_ID('Logistics.ResellerRestockingSessions')) as index_exists
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
" "AdventureWorks2022")

# 3. Get Table Column Info
echo "Checking table structure..."
COLUMNS_JSON=$(mssql_query "
    SELECT COLUMN_NAME, DATA_TYPE 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_SCHEMA = 'Logistics' AND TABLE_NAME = 'ResellerRestockingSessions'
    FOR JSON PATH
" "AdventureWorks2022")

# 4. Export Raw Reseller Data (for Python ground truth calculation)
# We export this so verifier.py can independently calculate what the sessions *should* be.
# Using 'OnlineOrderFlag = 0' for Resellers.
echo "Exporting raw source data..."
mssql_query_raw "
    SET NOCOUNT ON;
    SELECT CustomerID, CAST(OrderDate AS DATE) as OrderDate, TotalDue
    FROM Sales.SalesOrderHeader
    WHERE OnlineOrderFlag = 0
    ORDER BY CustomerID, OrderDate
" "AdventureWorks2022" > /tmp/raw_source_data.csv

# 5. Export Agent's Current Table Data (Result of their 7-day run)
echo "Exporting agent's current results..."
mssql_query_raw "
    SET NOCOUNT ON;
    SELECT CustomerID, CAST(SessionStartDate AS DATE), CAST(SessionEndDate AS DATE), OrderCount, TotalSessionValue, GapUsed
    FROM Logistics.ResellerRestockingSessions
    ORDER BY CustomerID, SessionStartDate
" "AdventureWorks2022" > /tmp/agent_result_7day.csv

# 6. ANTI-GAMING: Test Dynamic Logic
# We execute the agent's stored procedure with a DIFFERENT gap (21 days) to ensure it's not hardcoded.
echo "Testing dynamic logic (21 days)..."
DYNAMIC_TEST_SUCCESS="false"

# Run the proc with 21 days
mssql_query "EXEC Logistics.usp_GenerateRestockingSessions @MaxGapDays = 21" "AdventureWorks2022"

# Check if run was successful (table should have data with GapUsed=21)
CHECK_21=$(mssql_query "SELECT TOP 1 GapUsed FROM Logistics.ResellerRestockingSessions" "AdventureWorks2022" | tr -d ' \r\n')

if [[ "$CHECK_21" == "21" ]]; then
    DYNAMIC_TEST_SUCCESS="true"
    # Export the 21-day result for verification
    mssql_query_raw "
        SET NOCOUNT ON;
        SELECT CustomerID, CAST(SessionStartDate AS DATE), CAST(SessionEndDate AS DATE), OrderCount, TotalSessionValue, GapUsed
        FROM Logistics.ResellerRestockingSessions
        ORDER BY CustomerID, SessionStartDate
    " "AdventureWorks2022" > /tmp/agent_result_21day.csv
else
    echo "Dynamic test failed. Found GapUsed: $CHECK_21"
fi

# 7. Compile Result JSON
# (We handle the heavy lifting in Python, just passing paths and basic flags here)
cat > /tmp/task_result.json <<EOF
{
    "objects": $OBJECT_CHECK_JSON,
    "columns": $COLUMNS_JSON,
    "dynamic_test_run": $DYNAMIC_TEST_SUCCESS,
    "raw_source_path": "/tmp/raw_source_data.csv",
    "agent_7day_path": "/tmp/agent_result_7day.csv",
    "agent_21day_path": "/tmp/agent_result_21day.csv",
    "timestamp": "$(date +%s)"
}
EOF

# Permission fix
chmod 666 /tmp/task_result.json /tmp/*.csv

echo "Export complete."