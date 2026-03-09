#!/bin/bash
# Setup script for Apply Coupon to Order task

echo "=== Setting up Apply Coupon to Order Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial order count and existing order IDs for verification
echo "Recording initial order state..."
INITIAL_COUNT=$(get_order_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_order_count
echo "Initial order count: $INITIAL_COUNT"

# Record existing order IDs so the export script can exclude them
EXISTING_ORDER_IDS=$(wc_query "SELECT GROUP_CONCAT(ID) FROM wp_posts WHERE post_type='shop_order' AND post_status != 'auto-draft'" 2>/dev/null)
echo "${EXISTING_ORDER_IDS:-}" > /tmp/existing_order_ids
echo "Existing order IDs: ${EXISTING_ORDER_IDS:-none}"

# Verify prerequisite data exists
echo "Verifying prerequisite data..."

# Check products exist
YMP_DATA=$(get_product_by_sku "YMP-001" 2>/dev/null)
IWB_DATA=$(get_product_by_sku "IWB-032" 2>/dev/null)
echo "Yoga Mat Premium (YMP-001): $([ -n "$YMP_DATA" ] && echo "FOUND" || echo "NOT FOUND")"
echo "Insulated Water Bottle (IWB-032): $([ -n "$IWB_DATA" ] && echo "FOUND" || echo "NOT FOUND")"

# Check coupon exists
COUPON_DATA=$(get_coupon_by_code "WELCOME10" 2>/dev/null)
echo "Coupon WELCOME10: $([ -n "$COUPON_DATA" ] && echo "FOUND" || echo "NOT FOUND")"

# Check customer exists
CUSTOMER_DATA=$(get_customer_by_email "john.doe@example.com" 2>/dev/null)
echo "Customer John Doe: $([ -n "$CUSTOMER_DATA" ] && echo "FOUND" || echo "NOT FOUND")"

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

echo "=== Apply Coupon to Order Task Setup Complete ==="
echo "Agent should create a new order with specified products and apply WELCOME10 coupon."
