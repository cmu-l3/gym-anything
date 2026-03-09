#!/bin/bash
# Setup script for Create Coupon task (pre_task hook)
# Ensures Drupal Commerce admin is showing Promotions page

echo "=== Setting up Create Coupon Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial promotion/coupon counts for verification
echo "Recording initial promotion/coupon counts..."
INITIAL_PROMO_COUNT=$(get_promotion_count 2>/dev/null || echo "0")
INITIAL_COUPON_COUNT=$(get_coupon_count 2>/dev/null || echo "0")
echo "$INITIAL_PROMO_COUNT" > /tmp/initial_promotion_count
echo "$INITIAL_COUPON_COUNT" > /tmp/initial_coupon_count
chmod 666 /tmp/initial_promotion_count /tmp/initial_coupon_count
echo "Initial promotion count: $INITIAL_PROMO_COUNT"
echo "Initial coupon count: $INITIAL_COUPON_COUNT"

# Ensure all services (Docker, MariaDB, Apache, Firefox) are running
# This handles cases where post_start hook timed out or failed
echo "Verifying infrastructure services..."
ensure_services_running 90

# Ensure Drupal admin page is showing
echo "Ensuring Drupal admin page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
    echo "Attempting direct navigation..."
fi
echo "Drupal admin page setup attempted"

# Navigate to the Promotions admin page
echo "Navigating to Commerce > Promotions..."
navigate_firefox_to "http://localhost/admin/commerce/promotions"
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
echo "Initial screenshot saved - verify it shows Drupal Commerce Promotions page"

echo "=== Create Coupon Task Setup Complete ==="
echo "Agent should be on the Drupal Commerce Promotions admin page (already logged in)."
