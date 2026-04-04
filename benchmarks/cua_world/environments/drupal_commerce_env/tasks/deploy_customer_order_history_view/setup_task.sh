#!/bin/bash
# Setup script for deploy_customer_order_history_view
echo "=== Setting up deploy_customer_order_history_view ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Ensure services are running
ensure_services_running 120

# Ensure user 'janesmith' exists (uid 3 is standard in this env, but let's verify/create)
if ! drush user:information janesmith > /dev/null 2>&1; then
    echo "Creating user janesmith..."
    drush user:create janesmith --mail="jane.smith@example.com" --password="Customer123!"
fi
# Get the UID for janesmith to be sure
JANE_UID=$(drush user:information janesmith --fields=uid --format=string 2>/dev/null || echo "3")
echo "$JANE_UID" > /tmp/janesmith_uid
echo "Test user janesmith has UID: $JANE_UID"

# Clean up: Delete the view if it already exists (from previous run)
if drush config:get views.view.my_recent_orders > /dev/null 2>&1; then
    echo "Deleting existing view 'my_recent_orders'..."
    drush config:delete views.view.my_recent_orders -y
fi

# Clean up: Remove the block placement if exists
BLOCK_ID=$(drush config:list --prefix=block.block.views_block__my_recent_orders | head -n 1)
if [ -n "$BLOCK_ID" ]; then
    echo "Deleting existing block placement '$BLOCK_ID'..."
    drush config:delete "$BLOCK_ID" -y
fi

# Clear cache to ensure clean state
drush cr

# Record initial order count for janesmith (should be 0 or whatever exists)
INITIAL_USER_ORDER_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order WHERE uid=$JANE_UID")
echo "${INITIAL_USER_ORDER_COUNT:-0}" > /tmp/initial_user_order_count

# Navigate to Views admin page
echo "Navigating to Views list..."
navigate_firefox_to "http://localhost/admin/structure/views"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="