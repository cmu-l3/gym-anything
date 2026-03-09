#!/bin/bash
# Setup script for Configure Store Shipping task
echo "=== Setting up Configure Store Shipping ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Fallback for drupal_db_query if not in path
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 90

# Clean up any existing shipping methods to ensure clean state
# (In a real scenario we might append, but for grading it's safer to start clear or record baseline)
# We will record baseline instead of deleting to be less destructive, 
# though the description implies creating new ones.
INITIAL_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_shipping_method_field_data")
INITIAL_COUNT=${INITIAL_COUNT:-0}
echo "$INITIAL_COUNT" > /tmp/initial_shipping_count
echo "Initial shipping method count: $INITIAL_COUNT"

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure Drupal admin is reachable
if ! ensure_drupal_shown 60; then
    echo "WARNING: Drupal admin not immediately detected, attempting navigation..."
fi

# Navigate directly to Shipping Methods page to save agent time
echo "Navigating to Shipping Methods admin page..."
navigate_firefox_to "http://localhost/admin/commerce/shipping-methods"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="