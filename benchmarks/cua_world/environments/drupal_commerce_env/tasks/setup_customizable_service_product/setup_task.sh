#!/bin/bash
# Setup script for setup_customizable_service_product
echo "=== Setting up setup_customizable_service_product ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure services are running
ensure_services_running 90

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial state of config to prevent false positives from previous runs
# We want to ensure the agent actually creates these, although the verifier checks structure
# Removing any pre-existing config if this was run before (cleanup)
cd /var/www/html/drupal
$DRUSH config:delete commerce_order_item_type.service 2>/dev/null || true
$DRUSH config:delete commerce_product_type.service 2>/dev/null || true
$DRUSH config:delete field.storage.commerce_order_item.field_device_serial_number 2>/dev/null || true

# Ensure Drupal admin page is shown
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to Commerce Configuration page as a helpful starting point
navigate_firefox_to "http://localhost/admin/commerce/config"
sleep 5

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="