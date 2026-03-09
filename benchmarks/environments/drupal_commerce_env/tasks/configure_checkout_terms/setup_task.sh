#!/bin/bash
# Setup script for Configure Checkout Terms task
echo "=== Setting up Configure Checkout Terms Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure services are running
ensure_services_running 120

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Record initial state of checkout flow (to verify it actually changed)
cd /var/www/html/drupal
vendor/bin/drush config:get commerce_checkout.commerce_checkout_flow.default --format=json > /tmp/initial_checkout_config.json 2>/dev/null || echo "{}" > /tmp/initial_checkout_config.json

# 4. Cleanup: If a "Terms and Conditions" page already exists from a previous run, delete it to ensure a clean state
# This prevents the agent from just linking to an old page without creating a new one
EXISTING_NID=$(drupal_db_query "SELECT nid FROM node_field_data WHERE title='Terms and Conditions' LIMIT 1")
if [ -n "$EXISTING_NID" ]; then
    echo "Cleaning up existing Terms page (nid: $EXISTING_NID)..."
    cd /var/www/html/drupal
    vendor/bin/drush entity:delete node "$EXISTING_NID" 2>/dev/null || true
fi

# 5. Ensure Drupal admin is shown in Firefox
echo "Navigating Firefox to Commerce Configuration..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi
navigate_firefox_to "http://localhost/admin/commerce/config/orders"

# 6. Maximize window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="