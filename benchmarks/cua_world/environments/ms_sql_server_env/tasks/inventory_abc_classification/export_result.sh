#!/bin/bash
# Export results for inventory_abc_classification
echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Schema and View Existence
SCHEMA_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.schemas WHERE name = 'Inventory'" | tr -d ' \r\n')
VIEW_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_ABC_Classification_2013' AND schema_id = SCHEMA_ID('Inventory')" | tr -d ' \r\n')

# 2. Check View Column Structure
COLUMNS_FOUND=$(mssql_query "
    SELECT COLUMN_NAME 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_SCHEMA = 'Inventory' AND TABLE_NAME = 'vw_ABC_Classification_2013'
" | tr -d '\r' | tr '\n' ',' | tr '[:upper:]' '[:lower:]')

HAS_REQUIRED_COLS="false"
if [[ "$COLUMNS_FOUND" == *"productid"* && "$COLUMNS_FOUND" == *"name"* && "$COLUMNS_FOUND" == *"totalrevenue"* && "$COLUMNS_FOUND" == *"cumulativepct"* && "$COLUMNS_FOUND" == *"abc_class"* ]]; then
    HAS_REQUIRED_COLS="true"
fi

# 3. Data Validation - Row Counts
# Total Products in DB
TOTAL_DB_PRODUCTS=$(mssql_query "SELECT COUNT(*) FROM Production.Product" | tr -d ' \r\n')
# Rows in View
VIEW_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Inventory.vw_ABC_Classification_2013" 2>/dev/null | tr -d ' \r\n')

# 4. Data Validation - Logic Checks
# Check if unsold items are included (Revenue = 0)
UNSOLD_INCLUDED_COUNT=$(mssql_query "SELECT COUNT(*) FROM Inventory.vw_ABC_Classification_2013 WHERE TotalRevenue = 0 OR TotalRevenue IS NULL" 2>/dev/null | tr -d ' \r\n')

# Check Class A Count
CLASS_A_COUNT=$(mssql_query "SELECT COUNT(*) FROM Inventory.vw_ABC_Classification_2013 WHERE ABC_Class = 'A'" 2>/dev/null | tr -d ' \r\n')

# Check boundary logic: Max CumulativePct for Class A should be <= 0.8 (or close to it if one item bridges the gap, but usually strictly defined)
# Actually, Pareto usually says "up to 80%", so let's check the max Pct of A items
MAX_PCT_A=$(mssql_query "SELECT CAST(MAX(CumulativePct) AS DECIMAL(10,4)) FROM Inventory.vw_ABC_Classification_2013 WHERE ABC_Class = 'A'" 2>/dev/null | tr -d ' \r\n')

# Check Class C definition (Should include 0 revenue)
ZERO_REV_CLASS=$(mssql_query "SELECT TOP 1 ABC_Class FROM Inventory.vw_ABC_Classification_2013 WHERE TotalRevenue = 0" 2>/dev/null | tr -d ' \r\n')

# 5. CSV Export Check
CSV_PATH="/home/ga/Documents/exports/class_a_priority.csv"
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
CSV_ROW_COUNT=0
CSV_HEADER_VALID="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$CSV_MTIME" -ge "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
    
    # Check Header
    HEADER=$(head -n 1 "$CSV_PATH" | tr '[:upper:]' '[:lower:]')
    if [[ "$HEADER" == *"productid"* && "$HEADER" == *"name"* && "$HEADER" == *"abc_class"* ]]; then
        CSV_HEADER_VALID="true"
    fi
    
    # Count rows (minus header)
    CSV_ROW_COUNT=$(($(wc -l < "$CSV_PATH") - 1))
fi

# 6. Verify specific product calculation (Ground Truth)
# Pick a known high selling product in 2013
# ProductID 782 (Mountain-200 Black, 38)
# We calculate its 2013 revenue directly to compare with view
CALC_REV_782=$(mssql_query "
    SELECT CAST(SUM(LineTotal) AS DECIMAL(10,2))
    FROM Sales.SalesOrderDetail sod
    JOIN Sales.SalesOrderHeader soh ON sod.SalesOrderID = soh.SalesOrderID
    WHERE sod.ProductID = 782 AND YEAR(soh.OrderDate) = 2013
" | tr -d ' \r\n')

VIEW_REV_782=$(mssql_query "
    SELECT CAST(TotalRevenue AS DECIMAL(10,2)) 
    FROM Inventory.vw_ABC_Classification_2013 
    WHERE ProductID = 782
" 2>/dev/null | tr -d ' \r\n')


# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "schema_exists": $([ "$SCHEMA_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "view_exists": $([ "$VIEW_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "has_required_columns": $HAS_REQUIRED_COLUMNS,
    "total_db_products": ${TOTAL_DB_PRODUCTS:-0},
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "unsold_included_count": ${UNSOLD_INCLUDED_COUNT:-0},
    "class_a_count": ${CLASS_A_COUNT:-0},
    "max_pct_a": "${MAX_PCT_A:-0}",
    "zero_rev_class": "${ZERO_REV_CLASS:-Unknown}",
    "csv_exists": $CSV_EXISTS,
    "csv_created_during": $CSV_CREATED_DURING,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_header_valid": $CSV_HEADER_VALID,
    "calc_rev_782": "${CALC_REV_782:-0}",
    "view_rev_782": "${VIEW_REV_782:-0}",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="