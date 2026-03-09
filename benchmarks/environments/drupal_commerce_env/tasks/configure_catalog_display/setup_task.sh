#!/bin/bash
# Setup script for Configure Catalog Display task
echo "=== Setting up Configure Catalog Display Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure all services are running
ensure_services_running 90

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial configuration state for comparison (optional, but good for debugging)
echo "Recording initial configuration..."
cd /var/www/html/drupal
vendor/bin/drush cget core.entity_view_display.commerce_product.default.default --format=json > /tmp/initial_product_display.json 2>/dev/null || echo "{}" > /tmp/initial_product_display.json
vendor/bin/drush cget core.entity_view_display.commerce_product_variation.default.default --format=json > /tmp/initial_variation_display.json 2>/dev/null || echo "{}" > /tmp/initial_variation_display.json

# Ensure Drupal admin page is shown
echo "Ensuring Drupal admin page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to the main Commerce Configuration page to give a helpful starting point
# or just the dashboard. Let's go to Commerce overview.
navigate_firefox_to "http://localhost/admin/commerce"
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