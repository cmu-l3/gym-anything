#!/bin/bash
# Export results for seo_url_slug_generation task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Database State Verification
# ============================================================

# 1. Check Function Existence and Logic
FUNCTION_EXISTS="false"
FUNCTION_TEST_RESULT=""

CHECK_FN=$(mssql_query "SELECT OBJECT_ID('dbo.fn_CreateSlug', 'FN')" "AdventureWorks2022" | tr -d ' \r\n')
if [ "$CHECK_FN" != "NULL" ] && [ -n "$CHECK_FN" ]; then
    FUNCTION_EXISTS="true"
    # Test the function with a complex string
    # Input: "Test & Value / 123 + 456"
    # Expected: "test-value-123-456" (or similar depending on implementation)
    FUNCTION_TEST_RESULT=$(mssql_query "SELECT dbo.fn_CreateSlug('Test & Value / 123 + 456')" "AdventureWorks2022" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//' | head -n 3 | tail -n 1)
fi

# 2. Check View Existence and Columns
VIEW_EXISTS="false"
VIEW_COLUMNS=""
VIEW_DEPENDENCY="false"

CHECK_VIEW=$(mssql_query "SELECT OBJECT_ID('Production.vw_ProductSEO', 'V')" "AdventureWorks2022" | tr -d ' \r\n')
if [ "$CHECK_VIEW" != "NULL" ] && [ -n "$CHECK_VIEW" ]; then
    VIEW_EXISTS="true"
    VIEW_COLUMNS=$(mssql_query "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'vw_ProductSEO' ORDER BY ORDINAL_POSITION" "AdventureWorks2022" | tr -d '\r' | tr '\n' ',')
    
    # Check if view actually depends on the function (Anti-gaming)
    DEP_COUNT=$(mssql_query "SELECT COUNT(*) FROM sys.sql_expression_dependencies WHERE referencing_id = OBJECT_ID('Production.vw_ProductSEO') AND referenced_id = OBJECT_ID('dbo.fn_CreateSlug')" "AdventureWorks2022" | tr -d ' \r\n')
    if [ "$DEP_COUNT" -gt 0 ]; then
        VIEW_DEPENDENCY="true"
    fi
fi

# 3. Check View Logic (Standard Product)
# Product 771: Mountain-100 Silver, 38
# Expected Path: bikes/mountain-bikes/mountain-100-silver-38-771
SAMPLE_PATH_771=""
if [ "$VIEW_EXISTS" = "true" ]; then
    SAMPLE_PATH_771=$(mssql_query "SELECT FullURLPath FROM Production.vw_ProductSEO WHERE ProductID = 771" "AdventureWorks2022" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//' | head -n 3 | tail -n 1)
fi

# 4. Check View Logic (Edge Case - No Subcategory)
# Product 1: Adjustable Race
# Expected Path: uncategorized/general/adjustable-race-1
SAMPLE_PATH_1=""
if [ "$VIEW_EXISTS" = "true" ]; then
    SAMPLE_PATH_1=$(mssql_query "SELECT FullURLPath FROM Production.vw_ProductSEO WHERE ProductID = 1" "AdventureWorks2022" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//' | head -n 3 | tail -n 1)
fi

# ============================================================
# File Verification
# ============================================================
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_PATH="/home/ga/Documents/product_771_slug.json"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$FILE_PATH" | tr -d '\n\r')
fi

# ============================================================
# JSON Bundle
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "function_exists": $FUNCTION_EXISTS,
    "function_test_result": "$FUNCTION_TEST_RESULT",
    "view_exists": $VIEW_EXISTS,
    "view_columns": "$VIEW_COLUMNS",
    "view_dependency": $VIEW_DEPENDENCY,
    "sample_path_771": "$SAMPLE_PATH_771",
    "sample_path_1": "$SAMPLE_PATH_1",
    "file_exists": $FILE_EXISTS,
    "file_content": $(echo "$FILE_CONTENT" | jq -R . 2>/dev/null || echo "\"$FILE_CONTENT\""),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="