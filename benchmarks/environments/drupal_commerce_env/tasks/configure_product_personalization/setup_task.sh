#!/bin/bash
# Setup script for configure_product_personalization task

echo "=== Setting up Configure Product Personalization Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 90

# Ensure Drupal admin page is shown
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to Order Item Types configuration to give the agent a good starting point
# This is located at /admin/commerce/config/order-item-types
echo "Navigating to Order Item Types config..."
navigate_firefox_to "http://localhost/admin/commerce/config/order-item-types"
sleep 5

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Clean up any previous attempts (if re-running in same env)
# We want to ensure we start clean if the field was created in a previous run
echo "Checking for existing engraving fields to clean up..."
EXISTING_FIELD=$(cd /var/www/html/drupal && vendor/bin/drush config:list | grep "field.storage.commerce_order_item.field_engraving" || echo "")
if [ -n "$EXISTING_FIELD" ]; then
    echo "Cleaning up existing field: $EXISTING_FIELD"
    cd /var/www/html/drupal && vendor/bin/drush config:delete "$EXISTING_FIELD" -y 2>/dev/null || true
    # Also try to delete the instance
    cd /var/www/html/drupal && vendor/bin/drush config:delete "field.field.commerce_order_item.default.field_engraving_message" -y 2>/dev/null || true
    cd /var/www/html/drupal && vendor/bin/drush cr
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="