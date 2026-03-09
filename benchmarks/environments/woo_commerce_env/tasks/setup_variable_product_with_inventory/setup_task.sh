#!/bin/bash
echo "=== Setting up Variable Product with Inventory Task ==="

source /workspace/scripts/task_utils.sh

# Record initial state
echo "Recording initial state..."
INITIAL_PRODUCT_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='product' AND post_status='publish'" 2>/dev/null || echo "0")
echo "$INITIAL_PRODUCT_COUNT" > /tmp/setup_variable_product_initial_count

INITIAL_VARIATION_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_posts WHERE post_type='product_variation'" 2>/dev/null || echo "0")
echo "$INITIAL_VARIATION_COUNT" > /tmp/setup_variable_product_initial_variation_count

# Clean up any pre-existing product with this SKU (ensures do-nothing test returns 0)
EXISTING_PRODUCT=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='PMWS-001' LIMIT 1" 2>/dev/null)
if [ -n "$EXISTING_PRODUCT" ]; then
    # Delete variations first
    VARIATION_IDS=$(wc_query "SELECT GROUP_CONCAT(ID) FROM wp_posts WHERE post_parent=$EXISTING_PRODUCT AND post_type='product_variation'" 2>/dev/null)
    if [ -n "$VARIATION_IDS" ] && [ "$VARIATION_IDS" != "NULL" ]; then
        wc_query "DELETE FROM wp_postmeta WHERE post_id IN ($VARIATION_IDS)" 2>/dev/null
        wc_query "DELETE FROM wp_posts WHERE ID IN ($VARIATION_IDS)" 2>/dev/null
    fi
    wc_query "DELETE FROM wp_postmeta WHERE post_id=$EXISTING_PRODUCT" 2>/dev/null
    wc_query "DELETE FROM wp_term_relationships WHERE object_id=$EXISTING_PRODUCT" 2>/dev/null
    wc_query "DELETE FROM wp_posts WHERE ID=$EXISTING_PRODUCT" 2>/dev/null
    echo "Removed pre-existing product PMWS-001"
fi

# Record timestamp after cleanup
date +%s > /tmp/setup_variable_product_start_ts

# Verify cross-sell target exists
echo "Verifying cross-sell target product..."
MWS_DATA=$(get_product_by_sku "MWS-GRY-L" 2>/dev/null)
echo "Merino Wool Sweater (MWS-GRY-L): $([ -n "$MWS_DATA" ] && echo "FOUND" || echo "NOT FOUND")"

# Verify Clothing category exists
CLOTHING_CAT=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat' AND LOWER(t.name)='clothing' LIMIT 1" 2>/dev/null)
echo "Clothing category: $([ -n "$CLOTHING_CAT" ] && echo "FOUND (ID=$CLOTHING_CAT)" || echo "NOT FOUND")"

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

take_screenshot /tmp/setup_variable_product_start_screenshot.png

echo "=== Variable Product with Inventory Task Setup Complete ==="
