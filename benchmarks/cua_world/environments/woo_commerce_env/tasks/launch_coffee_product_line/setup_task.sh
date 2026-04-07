#!/bin/bash
echo "=== Setting up Launch Coffee Product Line Task ==="

source /workspace/scripts/task_utils.sh

# ================================================================
# Record initial state
# ================================================================
echo "Recording initial state..."

INITIAL_PRODUCT_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='product' AND post_status='publish'" 2>/dev/null || echo "0")
echo "$INITIAL_PRODUCT_COUNT" > /tmp/launch_coffee_initial_product_count

INITIAL_VARIATION_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='product_variation'" 2>/dev/null || echo "0")
echo "$INITIAL_VARIATION_COUNT" > /tmp/launch_coffee_initial_variation_count

# Use HPOS tables (wp_wc_orders) since WooCommerce has custom orders table enabled
INITIAL_ORDER_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_wc_orders WHERE type='shop_order' AND status != 'auto-draft'" 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/launch_coffee_initial_order_count

EXISTING_ORDER_IDS=$(wc_query "SELECT GROUP_CONCAT(id) FROM wp_wc_orders WHERE type='shop_order' AND status != 'auto-draft'" 2>/dev/null)
echo "${EXISTING_ORDER_IDS:-}" > /tmp/launch_coffee_existing_order_ids

EXISTING_COUPON_IDS=$(wc_query "SELECT GROUP_CONCAT(ID) FROM wp_posts WHERE post_type='shop_coupon'" 2>/dev/null)
echo "${EXISTING_COUPON_IDS:-}" > /tmp/launch_coffee_existing_coupon_ids

EXISTING_CAT_IDS=$(wc_query "SELECT GROUP_CONCAT(t.term_id) FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat'" 2>/dev/null)
echo "${EXISTING_CAT_IDS:-}" > /tmp/launch_coffee_existing_cat_ids

# ================================================================
# Clean up any pre-existing task data (ensures do-nothing test returns 0)
# ================================================================
echo "Cleaning up pre-existing data..."

# Remove product with SKU EYC-001 and its variations
EXISTING_PRODUCT=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='EYC-001' LIMIT 1" 2>/dev/null)
if [ -n "$EXISTING_PRODUCT" ]; then
    VARIATION_IDS=$(wc_query "SELECT GROUP_CONCAT(ID) FROM wp_posts WHERE post_parent=$EXISTING_PRODUCT AND post_type='product_variation'" 2>/dev/null)
    if [ -n "$VARIATION_IDS" ] && [ "$VARIATION_IDS" != "NULL" ]; then
        wc_query "DELETE FROM wp_postmeta WHERE post_id IN ($VARIATION_IDS)" 2>/dev/null
        wc_query "DELETE FROM wp_posts WHERE ID IN ($VARIATION_IDS)" 2>/dev/null
    fi
    wc_query "DELETE FROM wp_postmeta WHERE post_id=$EXISTING_PRODUCT" 2>/dev/null
    wc_query "DELETE FROM wp_term_relationships WHERE object_id=$EXISTING_PRODUCT" 2>/dev/null
    wc_query "DELETE FROM wp_posts WHERE ID=$EXISTING_PRODUCT" 2>/dev/null
    echo "Removed pre-existing product EYC-001"
fi

# Remove "Artisan Coffee" and "Single Origin" categories
for CAT_NAME in "Single Origin" "Artisan Coffee"; do
    EXISTING_CAT=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat' AND LOWER(t.name)=LOWER('$CAT_NAME') LIMIT 1" 2>/dev/null)
    if [ -n "$EXISTING_CAT" ]; then
        wc_query "DELETE tr FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.term_id=$EXISTING_CAT" 2>/dev/null
        wc_query "DELETE FROM wp_term_taxonomy WHERE term_id=$EXISTING_CAT" 2>/dev/null
        wc_query "DELETE FROM wp_terms WHERE term_id=$EXISTING_CAT" 2>/dev/null
        echo "Removed pre-existing '$CAT_NAME' category"
    fi
done

# Remove "Fragile Items" shipping class
EXISTING_SHIP_CLASS=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_shipping_class' AND (LOWER(t.name)='fragile items' OR t.slug='fragile-items') LIMIT 1" 2>/dev/null)
if [ -n "$EXISTING_SHIP_CLASS" ]; then
    wc_query "DELETE tr FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.term_id=$EXISTING_SHIP_CLASS AND tt.taxonomy='product_shipping_class'" 2>/dev/null
    wc_query "DELETE FROM wp_term_taxonomy WHERE term_id=$EXISTING_SHIP_CLASS AND taxonomy='product_shipping_class'" 2>/dev/null
    wc_query "DELETE FROM wp_terms WHERE term_id=$EXISTING_SHIP_CLASS" 2>/dev/null
    echo "Removed pre-existing 'Fragile Items' shipping class"
fi

# Remove COFFEE15 coupon
EXISTING_COUPON=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='shop_coupon' AND LOWER(post_title)='coffee15' LIMIT 1" 2>/dev/null)
if [ -n "$EXISTING_COUPON" ]; then
    wc_query "DELETE FROM wp_postmeta WHERE post_id=$EXISTING_COUPON" 2>/dev/null
    wc_query "DELETE FROM wp_posts WHERE ID=$EXISTING_COUPON" 2>/dev/null
    echo "Removed pre-existing COFFEE15 coupon"
fi

# Remove orders from emily.chen@example.com (if any from previous runs)
# Uses HPOS tables (wp_wc_orders) since custom orders table is enabled
EMILY_USER_ID=$(wc_query "SELECT ID FROM wp_users WHERE LOWER(user_email)='emily.chen@example.com' LIMIT 1" 2>/dev/null)
if [ -n "$EMILY_USER_ID" ]; then
    EMILY_ORDERS=$(wc_query "SELECT id FROM wp_wc_orders WHERE type='shop_order' AND status != 'auto-draft' AND customer_id='$EMILY_USER_ID'" 2>/dev/null)
    for ORDER_ID in $EMILY_ORDERS; do
        [ -z "$ORDER_ID" ] && continue
        wc_query "DELETE FROM wp_woocommerce_order_itemmeta WHERE order_item_id IN (SELECT order_item_id FROM wp_woocommerce_order_items WHERE order_id=$ORDER_ID)" 2>/dev/null
        wc_query "DELETE FROM wp_woocommerce_order_items WHERE order_id=$ORDER_ID" 2>/dev/null
        wc_query "DELETE FROM wp_comments WHERE comment_post_ID=$ORDER_ID" 2>/dev/null
        wc_query "DELETE FROM wp_wc_order_addresses WHERE order_id=$ORDER_ID" 2>/dev/null
        wc_query "DELETE FROM wp_wc_orders_meta WHERE order_id=$ORDER_ID" 2>/dev/null
        wc_query "DELETE FROM wp_wc_order_operational_data WHERE order_id=$ORDER_ID" 2>/dev/null
        wc_query "DELETE FROM wp_wc_order_stats WHERE order_id=$ORDER_ID" 2>/dev/null
        wc_query "DELETE FROM wp_wc_orders WHERE id=$ORDER_ID" 2>/dev/null
        echo "Removed pre-existing HPOS order $ORDER_ID for emily.chen@example.com"
    done
fi

# ================================================================
# Record timestamp AFTER cleanup
# ================================================================
date +%s > /tmp/launch_coffee_start_ts

# ================================================================
# Ensure customer Emily Chen exists
# ================================================================
echo "Ensuring customer Emily Chen exists..."
EMILY_EXISTS=$(get_customer_by_email "emily.chen@example.com" 2>/dev/null)
if [ -z "$EMILY_EXISTS" ]; then
    cd /var/www/html/wordpress 2>/dev/null || true
    wp user create emily.chen emily.chen@example.com \
        --role=customer \
        --first_name="Emily" \
        --last_name="Chen" \
        --user_pass="Customer1234!" \
        --allow-root 2>/dev/null || true
    echo "Created customer Emily Chen"
else
    echo "Customer Emily Chen already exists"
fi

# ================================================================
# Verify prerequisite products exist
# ================================================================
echo "Verifying prerequisite products..."
for SKU in "OCT-BLK-M" "WBH-001"; do
    DATA=$(get_product_by_sku "$SKU" 2>/dev/null)
    echo "Product $SKU: $([ -n "$DATA" ] && echo "FOUND" || echo "NOT FOUND")"
done

# ================================================================
# Ensure WordPress admin page is displayed
# ================================================================
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page"
    exit 1
fi
echo "WordPress admin page confirmed loaded"

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/launch_coffee_start_screenshot.png

echo "=== Launch Coffee Product Line Task Setup Complete ==="
