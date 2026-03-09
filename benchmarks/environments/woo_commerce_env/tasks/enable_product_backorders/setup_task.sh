#!/bin/bash
# Setup script for Enable Product Backorders task

echo "=== Setting up Enable Product Backorders Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Identify Target Product
echo "Locating target product..."
PRODUCT_DATA=$(get_product_by_sku "WBH-001" 2>/dev/null)

if [ -z "$PRODUCT_DATA" ]; then
    echo "ERROR: Target product WBH-001 not found. Seeding..."
    # Fallback: Create it if missing (should not happen in standard env)
    wp wc product create --name="Wireless Bluetooth Headphones" --sku="WBH-001" --regular_price="79.99" --type="simple" --user=admin --allow-root > /dev/null
    PRODUCT_DATA=$(get_product_by_sku "WBH-001" 2>/dev/null)
fi

PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1)
echo "Target Product ID: $PRODUCT_ID"
echo "$PRODUCT_ID" > /tmp/target_product_id.txt

# 2. Reset Product State
# - Stock: 0
# - Status: Out of Stock
# - Backorders: No
# - Low Stock Threshold: Default (delete meta if exists)
echo "Resetting product state..."

# Update core fields via WP-CLI
wp wc product update "$PRODUCT_ID" \
    --stock_quantity=0 \
    --manage_stock=true \
    --status=publish \
    --user=admin \
    --allow-root > /dev/null

# Directly update meta to ensure clean state
# Set backorders to 'no'
wc_query "UPDATE wp_postmeta SET meta_value='no' WHERE post_id=$PRODUCT_ID AND meta_key='_backorders'"
# Set stock status to 'outofstock'
wc_query "UPDATE wp_postmeta SET meta_value='outofstock' WHERE post_id=$PRODUCT_ID AND meta_key='_stock_status'"
# Remove specific low stock amount to use global default
wc_query "DELETE FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_low_stock_amount'"

# 3. Ensure Environment Readiness
# Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state configured."

echo "=== Setup Complete ==="