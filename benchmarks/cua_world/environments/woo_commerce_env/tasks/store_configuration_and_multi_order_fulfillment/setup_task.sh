#!/bin/bash
echo "=== Setting up Store Configuration and Multi-Order Fulfillment Task ==="

source /workspace/scripts/task_utils.sh

# Record initial state
echo "Recording initial state..."

INITIAL_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/store_config_multi_order_initial_count

EXISTING_ORDER_IDS=$(wc_query "SELECT GROUP_CONCAT(ID) FROM wp_posts WHERE post_type='shop_order' AND post_status != 'auto-draft'" 2>/dev/null)
echo "${EXISTING_ORDER_IDS:-}" > /tmp/store_config_multi_order_existing_ids

# Clean up: Disable COD payment method
cd /var/www/html/wordpress 2>/dev/null || true
wp option update woocommerce_cod_settings '{"enabled":"no","title":"Cash on delivery","description":"","instructions":""}' --format=json --allow-root 2>/dev/null || true
echo "Disabled COD payment method"

# Clean up: Remove 'Oversized Items' shipping class if exists
OVERSIZED_TERM_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_shipping_class' AND (LOWER(t.name)='oversized items' OR t.slug='oversized-items') LIMIT 1" 2>/dev/null)
if [ -n "$OVERSIZED_TERM_ID" ]; then
    wc_query "DELETE tr FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.term_id=$OVERSIZED_TERM_ID AND tt.taxonomy='product_shipping_class'" 2>/dev/null
    wc_query "DELETE FROM wp_term_taxonomy WHERE term_id=$OVERSIZED_TERM_ID AND taxonomy='product_shipping_class'" 2>/dev/null
    wc_query "DELETE FROM wp_terms WHERE term_id=$OVERSIZED_TERM_ID" 2>/dev/null
    echo "Removed pre-existing 'Oversized Items' shipping class"
fi

# Clear shipping class from target products
for SKU in "PCH-DUO" "CPP-SET3"; do
    PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='$SKU' LIMIT 1" 2>/dev/null)
    if [ -n "$PRODUCT_ID" ]; then
        # Remove any shipping class assignments
        wc_query "DELETE tr FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tr.object_id=$PRODUCT_ID AND tt.taxonomy='product_shipping_class'" 2>/dev/null
        echo "Cleared shipping class for $SKU"
    fi
done

# Record timestamp after cleanup
date +%s > /tmp/store_config_multi_order_start_ts

# Verify prerequisite products exist
echo "Verifying prerequisite products..."
for SKU in "WBH-001" "USBC-065" "SFDJ-BLU-32" "MWS-GRY-L" "PCH-DUO" "CPP-SET3"; do
    DATA=$(get_product_by_sku "$SKU" 2>/dev/null)
    echo "Product $SKU: $([ -n "$DATA" ] && echo "FOUND" || echo "NOT FOUND")"
done

# Verify customers exist
for EMAIL in "mike.wilson@example.com" "john.doe@example.com"; do
    DATA=$(get_customer_by_email "$EMAIL" 2>/dev/null)
    echo "Customer $EMAIL: $([ -n "$DATA" ] && echo "FOUND" || echo "NOT FOUND")"
done

# Ensure WordPress admin page is displayed
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page"
    exit 1
fi
echo "WordPress admin page confirmed loaded"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/store_config_multi_order_start_screenshot.png

echo "=== Store Configuration and Multi-Order Fulfillment Task Setup Complete ==="
