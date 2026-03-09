#!/bin/bash
# Export script for Add to Cart task
# Queries the Drupal database for verification data and saves to JSON

echo "=== Exporting Add to Cart Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get initial order count recorded by setup_task.sh
INITIAL_ORDER_COUNT=$(cat /tmp/initial_order_count 2>/dev/null || echo "0")

# Get current order count (cart = draft order)
CURRENT_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")

echo "Order count: initial=$INITIAL_ORDER_COUNT, current=$CURRENT_ORDER_COUNT"

# Check for cart orders (type='default', state='draft' or cart_id is set)
CART_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order WHERE state = 'draft'" 2>/dev/null || echo "0")
echo "Cart (draft order) count: $CART_COUNT"

# Check if the expected product is in any cart
EXPECTED_SKU="SONY-WH1000XM5"
EXPECTED_TITLE="Sony WH-1000XM5 Wireless Headphones"
echo "Checking if '$EXPECTED_TITLE' (SKU: $EXPECTED_SKU) is in a cart..."

# Look for order items that reference the expected product variation
VARIATION_ID=$(get_variation_by_sku "$EXPECTED_SKU" 2>/dev/null)
PRODUCT_IN_CART="false"
ORDER_ITEM_COUNT="0"
ORDER_ITEM_QUANTITY=""

if [ -n "$VARIATION_ID" ] && [ "$VARIATION_ID" != "" ]; then
    echo "Product variation ID for SKU '$EXPECTED_SKU': $VARIATION_ID"

    # Check order_item table for this variation
    ORDER_ITEM_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order_item WHERE purchased_entity = $VARIATION_ID" 2>/dev/null || echo "0")

    if [ "$ORDER_ITEM_COUNT" -gt "0" ] 2>/dev/null; then
        PRODUCT_IN_CART="true"
        ORDER_ITEM_QUANTITY=$(drupal_db_query "SELECT quantity FROM commerce_order_item WHERE purchased_entity = $VARIATION_ID ORDER BY order_item_id DESC LIMIT 1" 2>/dev/null || echo "0")
        echo "Product found in cart: $ORDER_ITEM_COUNT order item(s), quantity=$ORDER_ITEM_QUANTITY"
    else
        echo "Product variation exists but not found in any order item"
    fi
else
    echo "Could not find variation for SKU '$EXPECTED_SKU'"
fi

# Also check if any new order items exist (broader check)
TOTAL_ORDER_ITEMS=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order_item" 2>/dev/null || echo "0")
echo "Total order items in database: $TOTAL_ORDER_ITEMS"

# Check if there's a cart with any items
HAS_CART_WITH_ITEMS="false"
if [ "$CART_COUNT" -gt "0" ] 2>/dev/null && [ "$TOTAL_ORDER_ITEMS" -gt "0" ] 2>/dev/null; then
    HAS_CART_WITH_ITEMS="true"
fi

# Build result JSON
create_result_json /tmp/task_result.json \
    "initial_order_count=$INITIAL_ORDER_COUNT" \
    "current_order_count=$CURRENT_ORDER_COUNT" \
    "cart_count=$CART_COUNT" \
    "product_in_cart=$PRODUCT_IN_CART" \
    "order_item_count=$ORDER_ITEM_COUNT" \
    "order_item_quantity=$ORDER_ITEM_QUANTITY" \
    "total_order_items=$TOTAL_ORDER_ITEMS" \
    "has_cart_with_items=$HAS_CART_WITH_ITEMS" \
    "expected_sku=$(json_escape "$EXPECTED_SKU")" \
    "variation_id=$VARIATION_ID"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "Result JSON:"
cat /tmp/task_result.json

echo ""
echo "=== Export Complete ==="
