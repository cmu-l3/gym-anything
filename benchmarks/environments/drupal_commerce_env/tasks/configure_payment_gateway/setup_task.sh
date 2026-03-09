#!/bin/bash
# Setup script for configure_payment_gateway task
echo "=== Setting up configure_payment_gateway ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure services are running
ensure_services_running 120

# Record initial payment gateways to detect new ones later
# We use Drush to list existing gateway config names
echo "Recording initial payment gateways..."
cd /var/www/html/drupal
vendor/bin/drush config:list --prefix=commerce_payment.commerce_payment_gateway > /tmp/initial_gateways.txt 2>/dev/null || touch /tmp/initial_gateways.txt
cat /tmp/initial_gateways.txt

# Ensure Drupal admin page is shown and user is logged in
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate Firefox to the Payment Gateways list to give a helpful starting point
# URL: /admin/commerce/config/payment-gateways
echo "Navigating to Payment Gateways configuration..."
navigate_firefox_to "http://localhost/admin/commerce/config/payment-gateways"
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