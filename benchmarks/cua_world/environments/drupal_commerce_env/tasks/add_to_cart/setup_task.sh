#!/bin/bash
# Setup script for Add to Cart task (pre_task hook)
# Ensures Drupal Commerce storefront is showing the product catalog

echo "=== Setting up Add to Cart Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial order/cart count for verification
echo "Recording initial order/cart count..."
INITIAL_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count
chmod 666 /tmp/initial_order_count
echo "Initial order count: $INITIAL_ORDER_COUNT"

# Ensure all services (Docker, MariaDB, Apache, Firefox) are running
# This handles cases where post_start hook timed out or failed
echo "Verifying infrastructure services..."
ensure_services_running 90

# Ensure Drupal page is showing
echo "Ensuring Drupal page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal page, attempting navigation..."
fi

# Navigate to the product catalog page
echo "Navigating to storefront product listing..."
navigate_firefox_to "http://localhost/products"
sleep 5

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved - verify it shows Drupal Commerce storefront"

echo "=== Add to Cart Task Setup Complete ==="
echo "Agent should be on the Drupal Commerce storefront showing available products."
