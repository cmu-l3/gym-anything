#!/bin/bash
# Setup script for Setup Volume Discount task
echo "=== Setting up Setup Volume Discount Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Fallback definition if task_utils didn't load correctly
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure all services are running
ensure_services_running 90

# Clean up any existing promotion that might conflict (idempotency)
echo "Cleaning up any existing 'Volume Discount' promotions..."
EXISTING_IDS=$(drupal_db_query "SELECT promotion_id FROM commerce_promotion_field_data WHERE name LIKE '%Volume Discount%'")
if [ -n "$EXISTING_IDS" ]; then
    # Delete related data first to satisfy foreign keys if needed, though Drupal usually cascades
    drupal_db_query "DELETE FROM commerce_promotion_field_data WHERE name LIKE '%Volume Discount%'"
    echo "Removed existing promotions with similar name."
fi

# Record initial promotion count
INITIAL_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
INITIAL_PROMO_COUNT=${INITIAL_PROMO_COUNT:-0}
echo "$INITIAL_PROMO_COUNT" > /tmp/initial_promo_count
echo "Initial promotion count: $INITIAL_PROMO_COUNT"

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure Drupal admin page is showing
echo "Ensuring Drupal admin page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to the Promotions admin page
echo "Navigating to Commerce > Promotions..."
navigate_firefox_to "http://localhost/admin/commerce/promotions"
sleep 5

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="