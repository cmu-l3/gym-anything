#!/bin/bash
# Export script for Import Products CSV task

echo "=== Exporting Import Products CSV Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable", "success": false}' > /tmp/task_result.json
    echo "=== Export Failed: Database Unreachable ==="
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get counts
INITIAL_COUNT=$(cat /tmp/initial_product_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_product_count 2>/dev/null || echo "0")
COUNT_DELTA=$((CURRENT_COUNT - INITIAL_COUNT))

echo "Product count: Initial=$INITIAL_COUNT, Current=$CURRENT_COUNT, Delta=$COUNT_DELTA"

# Define expected SKUs
EXPECTED_SKUS=("HMJ-RNG-001" "HMP-TBL-002" "HMD-MWH-003" "HMA-SCS-004" "HMP-DPS-005" "HMJ-NKL-006" "HMD-CTR-007" "HMP-VAS-008")

# Initialize JSON array construction
PRODUCTS_JSON="["
FIRST=true

# Check each expected product
for SKU in "${EXPECTED_SKUS[@]}"; do
    echo "Checking for SKU: $SKU"
    
    # Fetch product data by SKU
    # Query returns: ID, SKU (we know SKU), Title, Regular Price, Post Date
    # We need to do a join to get price and categories
    
    # 1. Get ID and Title
    PROD_INFO=$(wc_query "SELECT p.ID, p.post_title, p.post_date 
                         FROM wp_posts p 
                         JOIN wp_postmeta pm ON p.ID = pm.post_id 
                         WHERE p.post_type='product' 
                         AND pm.meta_key='_sku' 
                         AND pm.meta_value='$SKU' 
                         LIMIT 1" 2>/dev/null)
    
    if [ -n "$PROD_INFO" ]; then
        PID=$(echo "$PROD_INFO" | cut -f1)
        TITLE=$(echo "$PROD_INFO" | cut -f2)
        POST_DATE=$(echo "$PROD_INFO" | cut -f3)
        
        # 2. Get Price
        PRICE=$(get_product_price "$PID" 2>/dev/null)
        
        # 3. Get Categories
        CATS=$(get_product_categories "$PID" 2>/dev/null)
        
        # Check creation time vs task start
        # Convert post_date (YYYY-MM-DD HH:MM:SS) to timestamp
        POST_TS=$(date -d "$POST_DATE" +%s 2>/dev/null || echo "0")
        
        CREATED_DURING_TASK="false"
        if [ "$POST_TS" -ge "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        fi
        
        FOUND="true"
    else
        FOUND="false"
        PID=""
        TITLE=""
        PRICE=""
        CATS=""
        CREATED_DURING_TASK="false"
    fi
    
    # Escape strings for JSON
    TITLE_ESC=$(json_escape "$TITLE")
    CATS_ESC=$(json_escape "$CATS")
    
    # Append to JSON array
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        PRODUCTS_JSON="$PRODUCTS_JSON,"
    fi
    
    PRODUCTS_JSON="$PRODUCTS_JSON {
        \"sku\": \"$SKU\",
        \"found\": $FOUND,
        \"id\": \"$PID\",
        \"name\": \"$TITLE_ESC\",
        \"price\": \"$PRICE\",
        \"categories\": \"$CATS_ESC\",
        \"created_during_task\": $CREATED_DURING_TASK
    }"
done

PRODUCTS_JSON="$PRODUCTS_JSON]"

# Check if CSV file still exists (it should)
CSV_EXISTS="false"
if [ -f "/home/ga/Documents/craft_products_import.csv" ]; then
    CSV_EXISTS="true"
fi

# Create final JSON
TEMP_JSON=$(mktemp /tmp/import_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "count_delta": $COUNT_DELTA,
    "csv_exists": $CSV_EXISTS,
    "imported_products": $PRODUCTS_JSON,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Safe move
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="