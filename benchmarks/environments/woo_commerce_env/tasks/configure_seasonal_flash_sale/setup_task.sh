#!/bin/bash
echo "=== Setting up Configure Seasonal Flash Sale Task ==="

source /workspace/scripts/task_utils.sh

# Record initial state for do-nothing test and baseline comparison
echo "Recording initial state..."

# Record existing coupon IDs to exclude pre-existing coupons
EXISTING_COUPON_IDS=$(wc_query "SELECT GROUP_CONCAT(ID) FROM wp_posts WHERE post_type='shop_coupon'" 2>/dev/null)
echo "${EXISTING_COUPON_IDS:-}" > /tmp/configure_seasonal_flash_sale_existing_coupon_ids

# Record existing product category IDs
EXISTING_CAT_IDS=$(wc_query "SELECT GROUP_CONCAT(t.term_id) FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat'" 2>/dev/null)
echo "${EXISTING_CAT_IDS:-}" > /tmp/configure_seasonal_flash_sale_existing_cat_ids

# Clear any pre-existing sale prices on target products (ensures do-nothing test returns 0)
for SKU in "WBH-001" "YMP-001" "LED-DL-01"; do
    PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='$SKU' LIMIT 1" 2>/dev/null)
    if [ -n "$PRODUCT_ID" ]; then
        wc_query "DELETE FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_sale_price'" 2>/dev/null
        wc_query "UPDATE wp_postmeta SET meta_value='' WHERE post_id=$PRODUCT_ID AND meta_key='_price' AND meta_value != (SELECT m2.meta_value FROM (SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_regular_price') m2)" 2>/dev/null || true
        echo "Cleared sale price for $SKU (product ID=$PRODUCT_ID)"
    fi
done

# Delete any existing "Flash Sale" category (clean slate)
EXISTING_FLASH_CAT=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat' AND LOWER(t.name)='flash sale' LIMIT 1" 2>/dev/null)
if [ -n "$EXISTING_FLASH_CAT" ]; then
    wc_query "DELETE tr FROM wp_term_relationships tr JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.term_id=$EXISTING_FLASH_CAT" 2>/dev/null
    wc_query "DELETE FROM wp_term_taxonomy WHERE term_id=$EXISTING_FLASH_CAT" 2>/dev/null
    wc_query "DELETE FROM wp_terms WHERE term_id=$EXISTING_FLASH_CAT" 2>/dev/null
    echo "Removed pre-existing 'Flash Sale' category"
fi

# Delete any existing FLASH30 coupon (clean slate)
EXISTING_FLASH_COUPON=$(wc_query "SELECT ID FROM wp_posts WHERE post_type='shop_coupon' AND LOWER(post_title)='flash30' LIMIT 1" 2>/dev/null)
if [ -n "$EXISTING_FLASH_COUPON" ]; then
    wc_query "DELETE FROM wp_postmeta WHERE post_id=$EXISTING_FLASH_COUPON" 2>/dev/null
    wc_query "DELETE FROM wp_posts WHERE ID=$EXISTING_FLASH_COUPON" 2>/dev/null
    echo "Removed pre-existing FLASH30 coupon"
fi

# Record timestamp AFTER cleanup
date +%s > /tmp/configure_seasonal_flash_sale_start_ts

# Verify prerequisite products exist
echo "Verifying prerequisite products..."
for SKU in "WBH-001" "YMP-001" "LED-DL-01"; do
    DATA=$(get_product_by_sku "$SKU" 2>/dev/null)
    echo "Product $SKU: $([ -n "$DATA" ] && echo "FOUND" || echo "NOT FOUND")"
done

# Ensure WordPress admin page is displayed
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

take_screenshot /tmp/configure_seasonal_flash_sale_start_screenshot.png

echo "=== Configure Seasonal Flash Sale Task Setup Complete ==="
