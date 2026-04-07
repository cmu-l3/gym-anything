#!/bin/bash
# Export results for multidimensional_sales_cube task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initial variables
TVF_EXISTS="false"
VIEW_EXISTS="false"
PROC_EXISTS="false"
TABLE_EXISTS="false"
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
CROSS_APPLY_USED="false"
TVF_IS_INLINE="false"
ROW_COUNT=0
DISTINCT_LEVELS=0
GRAND_TOTAL_REV=0
REF_REVENUE=0
GRAND_TOTAL_ROW_EXISTS="false"
CATEGORY_SUBTOTALS_COUNT=0
COLUMN_COUNT=0
REPORT_CONTENT_VALID="false"

# Check if SQL Server is running
if mssql_is_running; then

    # 1. Check Object Existence
    OBJECTS_CHECK=$(mssql_query "
        SELECT name, type 
        FROM sys.objects 
        WHERE name IN ('fn_SalesCube', 'vw_SalesCubeSummary', 'usp_ExportSalesCube', 'SalesCubeExport')
    " "AdventureWorks2022")

    if echo "$OBJECTS_CHECK" | grep -q "fn_SalesCube"; then TVF_EXISTS="true"; fi
    if echo "$OBJECTS_CHECK" | grep -q "vw_SalesCubeSummary"; then VIEW_EXISTS="true"; fi
    if echo "$OBJECTS_CHECK" | grep -q "usp_ExportSalesCube"; then PROC_EXISTS="true"; fi
    if echo "$OBJECTS_CHECK" | grep -q "SalesCubeExport"; then TABLE_EXISTS="true"; fi

    # Check if TVF is actually Inline Table-Valued Function (type 'IF')
    if echo "$OBJECTS_CHECK" | grep "fn_SalesCube" | grep -q "IF"; then
        TVF_IS_INLINE="true"
    fi

    # 2. Check View Definition for CROSS APPLY
    if [ "$VIEW_EXISTS" = "true" ]; then
        VIEW_DEF=$(mssql_query "SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('dbo.vw_SalesCubeSummary')" "AdventureWorks2022")
        if echo "$VIEW_DEF" | grep -qi "CROSS APPLY"; then
            CROSS_APPLY_USED="true"
        fi
    fi

    # 3. Validation of Table Content
    if [ "$TABLE_EXISTS" = "true" ]; then
        # Row Count
        ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.SalesCubeExport" "AdventureWorks2022" | tr -d ' \r\n')
        ROW_COUNT=${ROW_COUNT:-0}

        # Column Count
        COLUMN_COUNT=$(mssql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'SalesCubeExport'" "AdventureWorks2022" | tr -d ' \r\n')
        
        # Distinct Grouping Levels (should be > 1 if ROLLUP/CUBE/GROUPING SETS used)
        DISTINCT_LEVELS=$(mssql_query "SELECT COUNT(DISTINCT GroupingLevel) FROM dbo.SalesCubeExport" "AdventureWorks2022" | tr -d ' \r\n')
        DISTINCT_LEVELS=${DISTINCT_LEVELS:-0}

        # Check for Grand Total Row (where dimensions are NULL)
        # Note: We check for rows where all main dimensions are NULL. 
        # Using a loose check to accommodate variable column names, but assuming standard ones.
        GRAND_TOTAL_REV=$(mssql_query "
            SELECT TOP 1 TotalRevenue 
            FROM dbo.SalesCubeExport 
            WHERE CategoryName IS NULL 
              AND TerritoryGroup IS NULL 
              AND CalendarYear IS NULL
        " "AdventureWorks2022" | tr -d ' \r\n')
        
        if [ -n "$GRAND_TOTAL_REV" ] && [ "$GRAND_TOTAL_REV" != "NULL" ]; then
            GRAND_TOTAL_ROW_EXISTS="true"
        fi

        # Check Category Subtotals (Category NOT NULL, others NULL)
        CATEGORY_SUBTOTALS_COUNT=$(mssql_query "
            SELECT COUNT(*) 
            FROM dbo.SalesCubeExport 
            WHERE CategoryName IS NOT NULL 
              AND SubcategoryName IS NULL 
              AND TerritoryGroup IS NULL 
              AND CalendarYear IS NULL
        " "AdventureWorks2022" | tr -d ' \r\n')
    fi
fi

# 4. Check Report File
REPORT_PATH="/home/ga/Documents/exports/sales_cube_report.txt"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    
    # Check timestamp
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi

    # Check content (should contain dollar sign or big number, and some text)
    if grep -qE "[0-9,]{7,}" "$REPORT_PATH"; then
        REPORT_CONTENT_VALID="true"
    fi
fi

# Get Reference Revenue from setup
REF_REVENUE=$(grep "Reference Revenue:" /tmp/initial_state.txt | cut -d':' -f2 | tr -d ' ')

# Build JSON result
cat > /tmp/cube_result.json << EOF
{
    "tvf_exists": $TVF_EXISTS,
    "tvf_is_inline": $TVF_IS_INLINE,
    "view_exists": $VIEW_EXISTS,
    "cross_apply_used": $CROSS_APPLY_USED,
    "proc_exists": $PROC_EXISTS,
    "table_exists": $TABLE_EXISTS,
    "row_count": $ROW_COUNT,
    "column_count": $COLUMN_COUNT,
    "distinct_levels": $DISTINCT_LEVELS,
    "grand_total_row_exists": $GRAND_TOTAL_ROW_EXISTS,
    "grand_total_revenue": "${GRAND_TOTAL_REV:-0}",
    "reference_revenue": "${REF_REVENUE:-0}",
    "category_subtotals_count": ${CATEGORY_SUBTOTALS_COUNT:-0},
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_valid": $REPORT_CONTENT_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Permission fix
chmod 666 /tmp/cube_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/cube_result.json
echo "=== Export complete ==="