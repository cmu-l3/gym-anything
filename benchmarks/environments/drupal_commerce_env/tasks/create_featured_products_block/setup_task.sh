#!/bin/bash
# Setup script for Create Featured Products Block task

echo "=== Setting up Create Featured Products Block Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 120

# 1. Clean slate: Unpromote ALL products to ensure agent does the work
echo "Resetting product promotion status..."
drupal_db_query "UPDATE commerce_product_field_data SET promote = 0 WHERE 1=1"
echo "All products unpromoted."

# 2. Check if View already exists (from previous run) and delete it
echo "Checking for existing views..."
VIEW_EXISTS=$(drush_cmd config:status --state=Any | grep "views.view.staff_picks" || echo "")
if [ -n "$VIEW_EXISTS" ]; then
    echo "Deleting stale 'staff_picks' view..."
    drush_cmd config:delete "views.view.staff_picks" -y
fi

# 3. Check for existing block placement and delete it
BLOCK_EXISTS=$(drush_cmd config:list | grep "block.block.views_block__staff_picks" || echo "")
for block in $BLOCK_EXISTS; do
    echo "Deleting stale block placement: $block"
    drush_cmd config:delete "$block" -y
done

# Clear caches to ensure clean start
drush_cmd cr

# Record initial state
INITIAL_PROMOTED_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data WHERE promote = 1")
echo "$INITIAL_PROMOTED_COUNT" > /tmp/initial_promoted_count

# Ensure Drupal is accessible
ensure_drupal_shown 60

# Navigate to Products page to give the agent a starting point
echo "Navigating to Product list..."
navigate_firefox_to "http://localhost/admin/commerce/products"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="