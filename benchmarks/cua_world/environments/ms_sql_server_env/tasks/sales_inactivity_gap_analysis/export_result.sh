#!/bin/bash
echo "=== Exporting sales_inactivity_gap_analysis result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if artifacts exist
echo "Checking database objects..."
FUNC_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID(N'Sales.tvf_GetSalesPersonMaxGap') AND type IN (N'IF', N'TF')" | tr -d ' \r\n')
VIEW_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE object_id = OBJECT_ID(N'Sales.vw_2013_InactivityReport')" | tr -d ' \r\n')

# 2. Dynamic Verification: Test the function logic with injected data
# We will use a transaction to insert data, test, and rollback so we don't pollute the DB.
# We pick a SalesPersonID (e.g., 275) and insert two orders in 2028.
echo "Running dynamic logic verification..."

VERIFY_SQL="
BEGIN TRANSACTION;

-- 1. Identify a valid SalesPerson and Customer to use for fake data
DECLARE @TestSalesPersonID INT = 275; -- Michael Blythe
DECLARE @TestCustomerID INT;
SELECT TOP 1 @TestCustomerID = CustomerID FROM Sales.Customer WHERE StoreID IS NOT NULL;

-- 2. Insert Fake Order 1: 2028-01-01
INSERT INTO Sales.SalesOrderHeader (
    RevisionNumber, OrderDate, DueDate, ShipDate, Status, OnlineOrderFlag, 
    PurchaseOrderNumber, AccountNumber, CustomerID, SalesPersonID, TerritoryID, 
    BillToAddressID, ShipToAddressID, ShipMethodID, SubTotal, TaxAmt, Freight
)
SELECT TOP 1 
    8, '2028-01-01', '2028-01-12', '2028-01-08', 5, 0, 
    'TEST-GAP-1', '10-4020-000676', @TestCustomerID, @TestSalesPersonID, TerritoryID, 
    BillToAddressID, ShipToAddressID, ShipMethodID, 100.00, 8.00, 2.50
FROM Sales.SalesOrderHeader WHERE SalesPersonID = @TestSalesPersonID;

-- 3. Insert Fake Order 2: 2028-01-10 (Gap should be Jan 2..9 = 8 days)
INSERT INTO Sales.SalesOrderHeader (
    RevisionNumber, OrderDate, DueDate, ShipDate, Status, OnlineOrderFlag, 
    PurchaseOrderNumber, AccountNumber, CustomerID, SalesPersonID, TerritoryID, 
    BillToAddressID, ShipToAddressID, ShipMethodID, SubTotal, TaxAmt, Freight
)
SELECT TOP 1 
    8, '2028-01-10', '2028-01-21', '2028-01-17', 5, 0, 
    'TEST-GAP-2', '10-4020-000676', @TestCustomerID, @TestSalesPersonID, TerritoryID, 
    BillToAddressID, ShipToAddressID, ShipMethodID, 100.00, 8.00, 2.50
FROM Sales.SalesOrderHeader WHERE SalesPersonID = @TestSalesPersonID;

-- 4. Execute User Function
SELECT 
    MaxGapDays,
    GapStartDate,
    GapEndDate
FROM Sales.tvf_GetSalesPersonMaxGap('2028-01-01', '2028-12-31')
WHERE SalesPersonID = @TestSalesPersonID;

ROLLBACK TRANSACTION;
"

# Run the verification query and capture output
# We expect columns: MaxGapDays, GapStartDate, GapEndDate
# Expected output string: "8 2028-01-01 2028-01-10" (dates might vary in format depending on sqlcmd settings, usually YYYY-MM-DD)
DYNAMIC_RESULT=$(docker exec mssql-server /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "GymAnything#2024" -C \
    -d "AdventureWorks2022" \
    -Q "$VERIFY_SQL" -h -1 -W -s "," 2>/dev/null)

echo "Dynamic Result Raw: $DYNAMIC_RESULT"

# Parse Dynamic Result
LOGIC_PASS="false"
ACTUAL_GAP=""
if [[ "$DYNAMIC_RESULT" == *"8,2028-01-01,2028-01-10"* ]] || [[ "$DYNAMIC_RESULT" == *"8,2028-01-01 00:00:00.000,2028-01-10 00:00:00.000"* ]]; then
    LOGIC_PASS="true"
    ACTUAL_GAP="8"
else
    # Try to extract what we got
    ACTUAL_GAP=$(echo "$DYNAMIC_RESULT" | head -1)
fi

# 3. Check CSV Output
CSV_PATH="/home/ga/Documents/inactivity_report_2013.csv"
CSV_EXISTS="false"
CSV_ROWS=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Count lines, subtract header
    LINES=$(wc -l < "$CSV_PATH")
    CSV_ROWS=$((LINES - 1))
fi

# 4. JSON Generation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "function_exists": $([ "$FUNC_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "view_exists": $([ "$VIEW_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "logic_test_passed": $LOGIC_PASS,
    "logic_test_raw": "$ACTUAL_GAP",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to safe location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json