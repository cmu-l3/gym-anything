#!/bin/bash
# Export results for query_product_sales task
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

# Check if output file exists
OUTPUT_FILE="/home/ga/Documents/exports/top_products.csv"
OUTPUT_EXISTS="false"
OUTPUT_ROW_COUNT=0
OUTPUT_HAS_HEADERS="false"
KNOWN_PRODUCTS_FOUND=0
PRODUCTS_FOUND=""

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"

    # Count rows (excluding header)
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
    if [ "$TOTAL_LINES" -gt 0 ]; then
        # Check if first line looks like a header
        FIRST_LINE=$(head -1 "$OUTPUT_FILE")
        if echo "$FIRST_LINE" | grep -qi "product\|name\|quantity"; then
            OUTPUT_HAS_HEADERS="true"
            OUTPUT_ROW_COUNT=$((TOTAL_LINES - 1))
        else
            OUTPUT_ROW_COUNT=$TOTAL_LINES
        fi
    fi

    # Get first few product names found
    PRODUCTS_FOUND=$(tail -n +2 "$OUTPUT_FILE" 2>/dev/null | head -5 | cut -d',' -f1 | tr '\n' ';' | sed 's/;$//')

    # Check for known top products (case insensitive)
    # Extract just the product name column (first field) for validation
    # This prevents gaming by adding product names in unrelated columns
    PRODUCT_NAMES=$(cut -d',' -f1 "$OUTPUT_FILE" | tr -d '"' | tr '[:upper:]' '[:lower:]')

    for product in "AWC Logo Cap" "Water Bottle - 30 oz." "Sport-100 Helmet" "Long-Sleeve Logo Jersey" "Short-Sleeve Classic Jersey"; do
        product_lower=$(echo "$product" | tr '[:upper:]' '[:lower:]')
        # Use word-boundary matching on the product name column only
        if echo "$PRODUCT_NAMES" | grep -qF "$product_lower"; then
            KNOWN_PRODUCTS_FOUND=$((KNOWN_PRODUCTS_FOUND + 1))
        fi
    done
fi

# Validate with database query - get actual top 10 products with quantities
echo "Validating with database query..."
ACTUAL_TOP_PRODUCT=""
ACTUAL_TOP_QUANTITY=""
DB_TOP_PRODUCTS=""
VALUES_MATCH_COUNT=0
if [ "$MSSQL_RUNNING" = "true" ]; then
    # Get full top 10 with quantities for validation
    DB_TOP_PRODUCTS=$(mssql_query "
        SELECT TOP 10 p.Name, SUM(sod.OrderQty) as Qty
        FROM Sales.SalesOrderDetail sod
        JOIN Production.Product p ON sod.ProductID = p.ProductID
        GROUP BY p.Name
        ORDER BY SUM(sod.OrderQty) DESC
    " | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')

    # Extract first product name and quantity
    ACTUAL_TOP_PRODUCT=$(echo "$DB_TOP_PRODUCTS" | head -1 | cut -d'|' -f1 | sed 's/^[ \t]*//;s/[ \t]*$//' | tr -d ' ')
    ACTUAL_TOP_QUANTITY=$(echo "$DB_TOP_PRODUCTS" | head -1 | cut -d'|' -f2 | sed 's/^[ \t]*//;s/[ \t]*$//' | tr -d ' ')

    # If pipe delimiter didn't work, try space delimiter
    if [ -z "$ACTUAL_TOP_QUANTITY" ] || [ "$ACTUAL_TOP_QUANTITY" = "$ACTUAL_TOP_PRODUCT" ]; then
        ACTUAL_TOP_PRODUCT=$(echo "$DB_TOP_PRODUCTS" | head -1 | awk '{print $1" "$2" "$3" "$4}' | sed 's/[ \t]*$//')
        ACTUAL_TOP_QUANTITY=$(echo "$DB_TOP_PRODUCTS" | head -1 | awk '{print $NF}')
    fi

    # Validate CSV values against database
    # This prevents agents from hardcoding fake values
    if [ -f "$OUTPUT_FILE" ] && [ -n "$DB_TOP_PRODUCTS" ]; then
        echo "Cross-validating CSV values against database..."
        # For each product in CSV, check if quantity matches database (within 5% tolerance)
        while IFS=',' read -r csv_product csv_quantity rest; do
            # Skip header row
            if echo "$csv_product" | grep -qi "product\|name"; then
                continue
            fi
            # Clean values
            csv_product=$(echo "$csv_product" | tr -d '"' | sed 's/^[ \t]*//;s/[ \t]*$//')
            csv_quantity=$(echo "$csv_quantity" | tr -d '"' | sed 's/^[ \t]*//;s/[ \t]*$//')

            # Find this product in database results
            for db_line in $DB_TOP_PRODUCTS; do
                db_product=$(echo "$db_line" | awk '{print $1" "$2" "$3" "$4}' | sed 's/[ \t]*$//')
                db_qty=$(echo "$db_line" | awk '{print $NF}')

                # Case-insensitive partial match for product name
                csv_lower=$(echo "$csv_product" | tr '[:upper:]' '[:lower:]')
                db_lower=$(echo "$db_product" | tr '[:upper:]' '[:lower:]')

                if echo "$db_lower" | grep -qF "$csv_lower" || echo "$csv_lower" | grep -qF "$db_lower"; then
                    # Check if quantity matches (allowing 5% tolerance for rounding)
                    if [ -n "$csv_quantity" ] && [ -n "$db_qty" ]; then
                        # Simple integer comparison
                        if [ "$csv_quantity" = "$db_qty" ]; then
                            VALUES_MATCH_COUNT=$((VALUES_MATCH_COUNT + 1))
                        fi
                    fi
                    break
                fi
            done
        done < "$OUTPUT_FILE"
    fi
fi

# Check if output file contains the actual top product
# Only check the product name column (first field) to prevent gaming
CORRECT_TOP_PRODUCT="false"
if [ -n "$ACTUAL_TOP_PRODUCT" ] && [ -f "$OUTPUT_FILE" ]; then
    top_product_lower=$(echo "$ACTUAL_TOP_PRODUCT" | tr '[:upper:]' '[:lower:]')
    product_col=$(cut -d',' -f1 "$OUTPUT_FILE" | tr -d '"' | tr '[:upper:]' '[:lower:]')
    if echo "$product_col" | grep -qF "$top_product_lower"; then
        CORRECT_TOP_PRODUCT="true"
    fi
fi

# Calculate if values are valid (at least 3 out of 10 quantities match)
# Aligned with verifier.py threshold for consistency
VALUES_VALIDATED="false"
if [ "$VALUES_MATCH_COUNT" -ge 3 ]; then
    VALUES_VALIDATED="true"
fi

# Check row count is correct (10 rows)
CORRECT_ROW_COUNT="false"
if [ "$OUTPUT_ROW_COUNT" -eq 10 ]; then
    CORRECT_ROW_COUNT="true"
elif [ "$OUTPUT_ROW_COUNT" -ge 9 ] && [ "$OUTPUT_ROW_COUNT" -le 11 ]; then
    CORRECT_ROW_COUNT="partial"
fi

# Create JSON result in temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_row_count": $OUTPUT_ROW_COUNT,
    "output_has_headers": $OUTPUT_HAS_HEADERS,
    "correct_row_count": $([ "$CORRECT_ROW_COUNT" = "true" ] && echo "true" || echo "false"),
    "known_products_found": $KNOWN_PRODUCTS_FOUND,
    "correct_top_product": $CORRECT_TOP_PRODUCT,
    "actual_top_product": "$ACTUAL_TOP_PRODUCT",
    "actual_top_quantity": "$ACTUAL_TOP_QUANTITY",
    "products_found": "$PRODUCTS_FOUND",
    "values_match_count": $VALUES_MATCH_COUNT,
    "values_validated": $VALUES_VALIDATED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/query_result.json 2>/dev/null || sudo rm -f /tmp/query_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/query_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/query_result.json
chmod 666 /tmp/query_result.json 2>/dev/null || sudo chmod 666 /tmp/query_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/query_result.json"
cat /tmp/query_result.json
echo ""
echo "=== Export complete ==="
