#!/bin/bash
# Export results for create_customer_orders_view task
echo "=== Exporting task result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Check if SQL Server is running
MSSQL_RUNNING="false"
if mssql_is_running; then
    MSSQL_RUNNING="true"
fi

# Check if Azure Data Studio is running
ADS_RUNNING="false"
if ads_is_running; then
    ADS_RUNNING="true"
fi

# Check if view exists
VIEW_EXISTS="false"
VIEW_COLUMN_COUNT=0
HAS_REQUIRED_COLUMNS="false"
VIEW_ROW_COUNT=0
COLUMNS_FOUND=""

if [ "$MSSQL_RUNNING" = "true" ]; then
    # Check if view exists
    VIEW_CHECK=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_CustomerOrderSummary'" | tr -d ' \r\n')
    if [ "$VIEW_CHECK" -gt 0 ]; then
        VIEW_EXISTS="true"

        # Get column count
        VIEW_COLUMN_COUNT=$(mssql_query "
            SELECT COUNT(*)
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'vw_CustomerOrderSummary'
        " | tr -d ' \r\n')

        # Get column names
        COLUMNS_FOUND=$(mssql_query "
            SELECT COLUMN_NAME
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'vw_CustomerOrderSummary'
            ORDER BY ORDINAL_POSITION
        " | tr '\r\n' ',' | sed 's/,$//')

        # Check for required columns - use exact word matching
        REQUIRED_COLS=("CustomerID" "FirstName" "LastName" "TotalOrders" "TotalAmount" "LastOrderDate")
        FOUND_COUNT=0
        # Convert to lowercase for comparison
        columns_lower=$(echo "$COLUMNS_FOUND" | tr '[:upper:]' '[:lower:]')
        for col in "${REQUIRED_COLS[@]}"; do
            col_lower=$(echo "$col" | tr '[:upper:]' '[:lower:]')
            # Use word-boundary matching to ensure exact column name
            if echo "$columns_lower" | grep -qE "(^|,)${col_lower}(,|$)"; then
                FOUND_COUNT=$((FOUND_COUNT + 1))
            fi
        done

        # Require ALL 6 columns for full pass
        if [ "$FOUND_COUNT" -ge 6 ]; then
            HAS_REQUIRED_COLUMNS="true"
        fi

        # Get row count from view
        VIEW_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.vw_CustomerOrderSummary" 2>/dev/null | tr -d ' \r\n' || echo "0")

        # Get sample data
        SAMPLE_DATA=$(mssql_query "SELECT TOP 3 * FROM dbo.vw_CustomerOrderSummary" 2>/dev/null | head -10)

        # Validate column data types
        COLUMN_TYPES=$(mssql_query "
            SELECT COLUMN_NAME + ':' + DATA_TYPE
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'vw_CustomerOrderSummary'
            ORDER BY ORDINAL_POSITION
        " | tr '\r\n' ',' | sed 's/,$//')

        # ANTI-GAMING: Validate view returns REAL customer data from actual tables
        # Check that CustomerIDs in the view actually exist in Sales.Customer
        DATA_VALIDATED="false"
        DATA_MATCH_COUNT=0

        # Get 5 CustomerIDs from the view
        VIEW_CUSTOMER_IDS=$(mssql_query "SELECT TOP 5 CustomerID FROM dbo.vw_CustomerOrderSummary ORDER BY TotalOrders DESC" 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | head -5)

        if [ -n "$VIEW_CUSTOMER_IDS" ]; then
            for cust_id in $VIEW_CUSTOMER_IDS; do
                # Check if this CustomerID exists in the actual Sales.Customer table
                REAL_CHECK=$(mssql_query "SELECT COUNT(*) FROM Sales.Customer WHERE CustomerID = $cust_id" 2>/dev/null | tr -d ' \r\n')
                if [ "$REAL_CHECK" -gt 0 ]; then
                    DATA_MATCH_COUNT=$((DATA_MATCH_COUNT + 1))
                fi
            done
        fi

        # Require at least 3/5 CustomerIDs to be real
        if [ "$DATA_MATCH_COUNT" -ge 3 ]; then
            DATA_VALIDATED="true"
        fi

        # Also verify TotalOrders count matches actual order count for a sample customer
        ORDERS_VALIDATED="false"
        if [ -n "$VIEW_CUSTOMER_IDS" ]; then
            SAMPLE_CUST=$(echo "$VIEW_CUSTOMER_IDS" | head -1)
            if [ -n "$SAMPLE_CUST" ]; then
                # Get TotalOrders from view
                VIEW_ORDERS=$(mssql_query "SELECT TotalOrders FROM dbo.vw_CustomerOrderSummary WHERE CustomerID = $SAMPLE_CUST" 2>/dev/null | tr -d ' \r\n')
                # Get actual order count from SalesOrderHeader
                ACTUAL_ORDERS=$(mssql_query "SELECT COUNT(*) FROM Sales.SalesOrderHeader WHERE CustomerID = $SAMPLE_CUST" 2>/dev/null | tr -d ' \r\n')
                if [ "$VIEW_ORDERS" = "$ACTUAL_ORDERS" ]; then
                    ORDERS_VALIDATED="true"
                fi
            fi
        fi

        # Check for expected data types
        CORRECT_TYPES="true"
        # CustomerID should be int
        if ! echo "$COLUMN_TYPES" | grep -qi "customerid:int"; then
            CORRECT_TYPES="false"
        fi
        # TotalOrders should be int
        if ! echo "$COLUMN_TYPES" | grep -qi "totalorders:int"; then
            CORRECT_TYPES="false"
        fi
        # TotalAmount should be numeric/money/decimal
        if ! echo "$COLUMN_TYPES" | grep -qiE "totalamount:(money|decimal|numeric|float)"; then
            CORRECT_TYPES="false"
        fi
        # LastOrderDate should be date/datetime
        if ! echo "$COLUMN_TYPES" | grep -qiE "lastorderdate:(date|datetime)"; then
            CORRECT_TYPES="false"
        fi
    fi
fi

# Check if row count is reasonable (at least 100 customers with orders)
REASONABLE_ROW_COUNT="false"
if [ "$VIEW_ROW_COUNT" -ge 100 ]; then
    REASONABLE_ROW_COUNT="true"
fi

# Initialize variables if not set (view doesn't exist case)
CORRECT_TYPES=${CORRECT_TYPES:-"false"}
COLUMN_TYPES=${COLUMN_TYPES:-""}
DATA_VALIDATED=${DATA_VALIDATED:-"false"}
DATA_MATCH_COUNT=${DATA_MATCH_COUNT:-0}
ORDERS_VALIDATED=${ORDERS_VALIDATED:-"false"}

# Create JSON result in temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "view_exists": $VIEW_EXISTS,
    "view_column_count": $VIEW_COLUMN_COUNT,
    "has_required_columns": $HAS_REQUIRED_COLUMNS,
    "correct_data_types": $CORRECT_TYPES,
    "view_row_count": $VIEW_ROW_COUNT,
    "reasonable_row_count": $REASONABLE_ROW_COUNT,
    "data_validated": $DATA_VALIDATED,
    "data_match_count": $DATA_MATCH_COUNT,
    "orders_validated": $ORDERS_VALIDATED,
    "columns_found": "$COLUMNS_FOUND",
    "column_types": "$COLUMN_TYPES",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/view_result.json 2>/dev/null || sudo rm -f /tmp/view_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/view_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/view_result.json
chmod 666 /tmp/view_result.json 2>/dev/null || sudo chmod 666 /tmp/view_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/view_result.json"
cat /tmp/view_result.json
echo ""

if [ "$VIEW_EXISTS" = "true" ]; then
    echo "Sample data from view:"
    echo "$SAMPLE_DATA"
fi

echo ""
echo "=== Export complete ==="
