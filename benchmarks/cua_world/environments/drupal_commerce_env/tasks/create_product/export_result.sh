#!/bin/bash
# Export script for Create Product task
# Queries the Drupal database for verification data and saves to JSON

echo "=== Exporting Create Product Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get initial product count recorded by setup_task.sh
INITIAL_COUNT=$(cat /tmp/initial_product_count 2>/dev/null || echo "0")

# Get current product count
CURRENT_COUNT=$(get_product_count 2>/dev/null || echo "0")

echo "Product count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Look for the expected product by title (case-insensitive)
EXPECTED_TITLE="Organic Bamboo Wireless Charger"
echo "Checking for product '$EXPECTED_TITLE'..."

PRODUCT_ID=$(get_product_id_by_title "$EXPECTED_TITLE" 2>/dev/null)
PRODUCT_FOUND="false"
PRODUCT_TITLE=""
PRODUCT_SKU=""
PRODUCT_PRICE=""
PRODUCT_STATUS=""

if [ -n "$PRODUCT_ID" ] && [ "$PRODUCT_ID" != "" ]; then
    PRODUCT_FOUND="true"

    # Get product title
    PRODUCT_TITLE=$(drupal_db_query "SELECT title FROM commerce_product_field_data WHERE product_id = $PRODUCT_ID LIMIT 1" 2>/dev/null)

    # Get product status
    PRODUCT_STATUS_RAW=$(drupal_db_query "SELECT status FROM commerce_product_field_data WHERE product_id = $PRODUCT_ID LIMIT 1" 2>/dev/null)
    if [ "$PRODUCT_STATUS_RAW" = "1" ]; then
        PRODUCT_STATUS="published"
    else
        PRODUCT_STATUS="unpublished"
    fi

    # Get variation data (SKU, price) via product-variation relationship
    PRODUCT_SKU=$(drupal_db_query "SELECT v.sku FROM commerce_product_variation_field_data v INNER JOIN commerce_product__variations pv ON v.variation_id = pv.variations_target_id WHERE pv.entity_id = $PRODUCT_ID ORDER BY v.variation_id DESC LIMIT 1" 2>/dev/null)

    PRODUCT_PRICE=$(drupal_db_query "SELECT v.price__number FROM commerce_product_variation_field_data v INNER JOIN commerce_product__variations pv ON v.variation_id = pv.variations_target_id WHERE pv.entity_id = $PRODUCT_ID ORDER BY v.variation_id DESC LIMIT 1" 2>/dev/null)

    echo "Product found: ID=$PRODUCT_ID, Title='$PRODUCT_TITLE', SKU='$PRODUCT_SKU', Price=$PRODUCT_PRICE, Status=$PRODUCT_STATUS"
else
    echo "Product '$EXPECTED_TITLE' NOT found in database"

    # Check if any new product was added
    if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ] 2>/dev/null; then
        echo "Note: $(($CURRENT_COUNT - $INITIAL_COUNT)) new product(s) added, but not with expected title"
        # Try to find the newest product
        NEWEST=$(drupal_db_query "SELECT product_id, title FROM commerce_product_field_data ORDER BY product_id DESC LIMIT 1" 2>/dev/null)
        echo "Newest product: $NEWEST"
    fi
fi

# Also check by SKU as a fallback
EXPECTED_SKU="OBW-CHR-01"
SKU_VARIATION_ID=$(get_variation_by_sku "$EXPECTED_SKU" 2>/dev/null)
SKU_FOUND="false"
if [ -n "$SKU_VARIATION_ID" ] && [ "$SKU_VARIATION_ID" != "" ]; then
    SKU_FOUND="true"
    echo "SKU '$EXPECTED_SKU' found as variation ID=$SKU_VARIATION_ID"
fi

# Build result JSON
create_result_json /tmp/task_result.json \
    "initial_product_count=$INITIAL_COUNT" \
    "current_product_count=$CURRENT_COUNT" \
    "product_found=$PRODUCT_FOUND" \
    "product_id=$PRODUCT_ID" \
    "product_title=$(json_escape "$PRODUCT_TITLE")" \
    "product_sku=$(json_escape "$PRODUCT_SKU")" \
    "product_price=$PRODUCT_PRICE" \
    "product_status=$(json_escape "$PRODUCT_STATUS")" \
    "sku_found=$SKU_FOUND"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "Result JSON:"
cat /tmp/task_result.json

echo ""
echo "=== Export Complete ==="
