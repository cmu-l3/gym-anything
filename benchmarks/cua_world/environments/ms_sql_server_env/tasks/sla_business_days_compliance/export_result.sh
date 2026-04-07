#!/bin/bash
# Export results for SLA Business Days task

echo "=== Exporting SLA Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Check SQL Objects & Data
# ============================================================

# 1. Check Holiday Table
TABLE_EXISTS="false"
HOLIDAY_COUNT=0
if mssql_table_exists "Sales.HolidayReference" "AdventureWorks2022"; then
    TABLE_EXISTS="true"
    HOLIDAY_COUNT=$(mssql_query "SELECT COUNT(*) FROM Sales.HolidayReference" "AdventureWorks2022" | tr -d ' \r\n')
fi

# 2. Check Function Existence & Logic
FUNC_EXISTS="false"
TEST_WEEKEND_RES="-1"
TEST_HOLIDAY_RES="-1"
TEST_STANDARD_RES="-1"

# Check if function exists
FUNC_CHECK=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.fn_GetNetWorkingDays') AND type IN (N'FN', N'IF', N'TF', N'FS', N'FT')" "AdventureWorks2022" | tr -d ' \r\n')

if [ "$FUNC_CHECK" -gt 0 ]; then
    FUNC_EXISTS="true"
    
    # Run logic tests using the user's function
    
    # Test 1: Weekend (Fri 2011-07-08 to Mon 2011-07-11) -> Should be 1 (Mon only)
    TEST_WEEKEND_RES=$(mssql_query "SELECT dbo.fn_GetNetWorkingDays('2011-07-08', '2011-07-11')" "AdventureWorks2022" | tr -d ' \r\n')
    
    # Test 2: Holiday (Fri 2011-07-01 to Tue 2011-07-05) -> July 4 is Mon/Holiday.
    # Fri->Sat(0), Sat->Sun(0), Sun->Mon(0-Hol), Mon->Tue(1). Expected: 1
    TEST_HOLIDAY_RES=$(mssql_query "SELECT dbo.fn_GetNetWorkingDays('2011-07-01', '2011-07-05')" "AdventureWorks2022" | tr -d ' \r\n')
    
    # Test 3: Standard (Mon 2011-07-11 to Thu 2011-07-14) -> Tue, Wed, Thu. Expected: 3
    TEST_STANDARD_RES=$(mssql_query "SELECT dbo.fn_GetNetWorkingDays('2011-07-11', '2011-07-14')" "AdventureWorks2022" | tr -d ' \r\n')
fi

# 3. Check View
VIEW_EXISTS="false"
VIEW_ROW_COUNT=0
VIEW_COLS=""

VIEW_CHECK=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_ShippingSLABreach' AND schema_id = SCHEMA_ID('Sales')" "AdventureWorks2022" | tr -d ' \r\n')

if [ "$VIEW_CHECK" -gt 0 ]; then
    VIEW_EXISTS="true"
    # Get row count
    VIEW_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Sales.vw_ShippingSLABreach" "AdventureWorks2022" | tr -d ' \r\n')
    
    # Get columns
    VIEW_COLS=$(mssql_query "
        SELECT COLUMN_NAME 
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_SCHEMA = 'Sales' AND TABLE_NAME = 'vw_ShippingSLABreach'
    " "AdventureWorks2022" | tr '\r\n' ',' | sed 's/,$//')
fi

# 4. Check CSV Export
CSV_PATH="/home/ga/Documents/sla_breaches.csv"
CSV_EXISTS="false"
CSV_ROWS=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Count lines, subtract 1 for header
    TOTAL_LINES=$(wc -l < "$CSV_PATH")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

# 5. App State
ADS_RUNNING=$(pgrep -f "azuredatastudio" > /dev/null && echo "true" || echo "false")

# ============================================================
# Create Result JSON
# ============================================================

TEMP_JSON=$(mktemp /tmp/sla_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "ads_running": $ADS_RUNNING,
    "table_exists": $TABLE_EXISTS,
    "holiday_count": ${HOLIDAY_COUNT:-0},
    "func_exists": $FUNC_EXISTS,
    "test_weekend_res": "${TEST_WEEKEND_RES:-err}",
    "test_holiday_res": "${TEST_HOLIDAY_RES:-err}",
    "test_standard_res": "${TEST_STANDARD_RES:-err}",
    "view_exists": $VIEW_EXISTS,
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "view_columns": "$VIEW_COLS",
    "csv_exists": $CSV_EXISTS,
    "csv_row_count": $CSV_ROWS
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json