#!/bin/bash
# Setup script for Customize Checkout Flow task
echo "=== Setting up Customize Checkout Flow Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 90

# Record initial configuration hash for anti-gaming detection
# We use drush to get the raw config and hash it
echo "Recording initial config state..."
cd /var/www/html/drupal
INITIAL_CONFIG_HASH=$(vendor/bin/drush config:get commerce_checkout.commerce_checkout_flow.default --format=json 2>/dev/null | md5sum | awk '{print $1}')
echo "$INITIAL_CONFIG_HASH" > /tmp/initial_config_hash.txt
echo "Initial config hash: $INITIAL_CONFIG_HASH"

# Ensure Drupal admin is logged in and ready
if ! ensure_drupal_shown 60; then
    echo "WARNING: Drupal admin not detected, attempting force login..."
fi

# Navigate directly to the Checkout Flows page
# The URL for the default flow edit form is /admin/commerce/config/checkout-flows/manage/default
echo "Navigating to Checkout Flows configuration..."
navigate_firefox_to "http://localhost/admin/commerce/config/checkout-flows/manage/default"
sleep 5

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state captured."

echo "=== Setup Complete ==="