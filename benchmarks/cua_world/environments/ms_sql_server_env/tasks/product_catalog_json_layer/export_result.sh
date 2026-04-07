#!/bin/bash
# Export results for product_catalog_json_layer task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Check Database Objects
# ============================================================

# Check Export Procedure
EXPORT_PROC_EXISTS="false"
if [ "$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_ExportProductCatalog'" "AdventureWorks2022" | tr -d ' \r\n')" -gt 0 ]; then
    EXPORT_PROC_EXISTS="true"
fi

# Check Import Procedure
IMPORT_PROC_EXISTS="false"
if [ "$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_ImportProductReviews'" "AdventureWorks2022" | tr -d ' \r\n')" -gt 0 ]; then
    IMPORT_PROC_EXISTS="true"
fi

# Check Staging Table
STAGING_TABLE_EXISTS="false"
if [ "$(mssql_query "SELECT COUNT(*) FROM sys.tables WHERE name = 'ProductReviewStaging' AND schema_id = SCHEMA_ID('Production')" "AdventureWorks2022" | tr -d ' \r\n')" -gt 0 ]; then
    STAGING_TABLE_EXISTS="true"
fi

# Check Staging Table Columns
REQUIRED_COLS=("StagingID" "ProductID" "ReviewerName" "Rating" "Comments" "ImportedDate")
FOUND_COLS_COUNT=0
COLUMNS_LIST=""

if [ "$STAGING_TABLE_EXISTS" = "true" ]; then
    DB_COLS=$(mssql_query "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'ProductReviewStaging' AND TABLE_SCHEMA = 'Production'" "AdventureWorks2022")
    COLUMNS_LIST=$(echo "$DB_COLS" | tr '\n' ',' | sed 's/,$//')
    
    for col in "${REQUIRED_COLS[@]}"; do
        if echo "$DB_COLS" | grep -qi "$col"; then
            FOUND_COLS_COUNT=$((FOUND_COLS_COUNT + 1))
        fi
    done
fi

# Check Staging Table Data
ROW_COUNT=0
DATA_SAMPLE=""
DATA_VALID="false"

if [ "$STAGING_TABLE_EXISTS" = "true" ]; then
    ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.ProductReviewStaging" "AdventureWorks2022" | tr -d ' \r\n')
    
    # Check for specific reviewer from the prompt to verify correct import
    CHECK_REVIEWER=$(mssql_query "SELECT COUNT(*) FROM Production.ProductReviewStaging WHERE ReviewerName = 'David Ortiz' AND Rating = 5" "AdventureWorks2022" | tr -d ' \r\n')
    if [ "$CHECK_REVIEWER" -gt 0 ]; then
        DATA_VALID="true"
    fi
    
    DATA_SAMPLE=$(mssql_query "SELECT TOP 3 ReviewerName, Rating FROM Production.ProductReviewStaging" "AdventureWorks2022" | tr '\n' ';')
fi

# ============================================================
# Check Exported JSON File
# ============================================================
JSON_FILE="/home/ga/Documents/exports/product_catalog.json"
FILE_EXISTS="false"
FILE_SIZE=0
IS_VALID_JSON="false"
HAS_NESTED_STRUCTURE="false"
CONTAINS_BIKES="false"

if [ -f "$JSON_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$JSON_FILE")
    
    # Validate JSON syntax and structure using Python
    PYTHON_CHECK=$(python3 -c "
import json
import sys

try:
    with open('$JSON_FILE', 'r') as f:
        data = json.load(f)
    
    is_valid = True
    has_structure = False
    contains_bikes = False
    
    # Allow data to be a list (standard for FOR JSON) or dict (if wrapped)
    if isinstance(data, list):
        root = data
    elif isinstance(data, dict):
        # Handle case where root is wrapped or single object
        root = [data]
    else:
        root = []
        
    for item in root:
        # Check for Bikes category
        cat_name = item.get('CategoryName', '') or item.get('Name', '')
        if 'Bikes' in cat_name:
            contains_bikes = True
            
        # Check for nested subcategories
        # Keys might vary slightly depending on query (Subcategories, ProductSubcategories, etc)
        subcats = item.get('Subcategories') or item.get('ProductSubcategories') or item.get('Children')
        if subcats and isinstance(subcats, list) and len(subcats) > 0:
            # Check for nested products inside subcategory
            first_sub = subcats[0]
            products = first_sub.get('Products') or first_sub.get('Product') or first_sub.get('Children')
            if products and isinstance(products, list):
                has_structure = True

    print(f'{is_valid}|{has_structure}|{contains_bikes}')
except Exception as e:
    print(f'False|False|False')
")
    
    IS_VALID_JSON=$(echo "$PYTHON_CHECK" | cut -d'|' -f1)
    HAS_NESTED_STRUCTURE=$(echo "$PYTHON_CHECK" | cut -d'|' -f2)
    CONTAINS_BIKES=$(echo "$PYTHON_CHECK" | cut -d'|' -f3)
fi

# ============================================================
# Create Result JSON
# ============================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "export_proc_exists": $EXPORT_PROC_EXISTS,
    "import_proc_exists": $IMPORT_PROC_EXISTS,
    "staging_table_exists": $STAGING_TABLE_EXISTS,
    "columns_found_count": $FOUND_COLS_COUNT,
    "columns_list": "$COLUMNS_LIST",
    "staging_row_count": ${ROW_COUNT:-0},
    "staging_data_valid": $DATA_VALID,
    "file_exists": $FILE_EXISTS,
    "file_size": ${FILE_SIZE:-0},
    "is_valid_json": $IS_VALID_JSON,
    "has_nested_structure": $HAS_NESTED_STRUCTURE,
    "contains_bikes": $CONTAINS_BIKES,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="