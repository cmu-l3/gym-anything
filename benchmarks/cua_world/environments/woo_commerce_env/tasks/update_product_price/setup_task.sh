#!/bin/bash
# Setup script for Update Product Price task

echo "=== Setting up Update Product Price Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial state of target product
echo "Recording initial product state..."
TARGET_DATA=$(get_product_by_sku "WBH-001" 2>/dev/null)
if [ -n "$TARGET_DATA" ]; then
    TARGET_ID=$(echo "$TARGET_DATA" | cut -f1)
    ORIG_PRICE=$(get_product_price "$TARGET_ID" 2>/dev/null)
    ORIG_SALE=$(get_product_sale_price "$TARGET_ID" 2>/dev/null)
    echo "$TARGET_ID" > /tmp/target_product_id
    echo "$ORIG_PRICE" > /tmp/original_regular_price
    echo "$ORIG_SALE" > /tmp/original_sale_price
    echo "Target product: ID=$TARGET_ID, Regular Price=$ORIG_PRICE, Sale Price=$ORIG_SALE"
else
    echo "WARNING: Target product WBH-001 not found!"
    echo "" > /tmp/target_product_id
fi

# CRITICAL: Ensure WordPress admin page is showing (not blank Firefox tab)
# This uses the robust ensure_wordpress_shown function that checks window title
# for WordPress-specific text, not just "Firefox" or "Mozilla Firefox"
# MUST exit with failure if WordPress doesn't load - do NOT continue with blank browser
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    echo "Window title check failed. Firefox may show blank tab instead of WooCommerce."
    exit 1
fi
echo "WordPress admin page confirmed loaded"

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot (should show WordPress admin, NOT blank tab)
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved - verify it shows WordPress admin"

echo "=== Update Product Price Task Setup Complete ==="
echo "Agent should find 'Wireless Bluetooth Headphones' and update its prices."
