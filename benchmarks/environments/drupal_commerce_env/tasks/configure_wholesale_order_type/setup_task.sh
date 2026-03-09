#!/bin/bash
echo "=== Setting up Configure Wholesale Order Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 90

# Ensure Drupal admin page is showing
echo "Ensuring Drupal admin page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Ensure the target customer exists
echo "Ensuring customer 'mikewilson' exists..."
cd /var/www/html/drupal
if ! vendor/bin/drush user:information mikewilson > /dev/null 2>&1; then
    vendor/bin/drush user:create mikewilson --mail="mike.wilson@example.com" --password="Customer123!" 2>&1
    echo "Created user mikewilson"
else
    echo "User mikewilson already exists"
fi

# Record initial state (snapshot of existing order types)
echo "Recording initial configuration..."
cd /var/www/html/drupal
vendor/bin/drush php:eval "
  \$types = \Drupal\commerce_order\Entity\OrderType::loadMultiple();
  echo json_encode(array_keys(\$types));
" > /tmp/initial_order_types.json 2>/dev/null || echo "[]" > /tmp/initial_order_types.json

# Navigate to Order Types configuration to help agent start
# This is a logical starting point for the task
echo "Navigating to Order Types configuration..."
navigate_firefox_to "http://localhost/admin/commerce/config/order-types"
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

echo "=== Setup Complete ==="