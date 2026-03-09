#!/bin/bash
# Setup script for configure_tiered_promotions
echo "=== Setting up Configure Tiered Promotions Task ==="

source /workspace/scripts/task_utils.sh

# Ensure infrastructure is ready
ensure_services_running 120

# Record task start time
date +%s > /tmp/task_start_time

# Clean up any existing promotions that might conflict or confuse the verification
# We delete any promotion containing "Tier" or specific discount amounts to ensure a clean slate
echo "Cleaning up existing conflicting promotions..."
drupal_db_query "DELETE FROM commerce_promotion_field_data WHERE name LIKE '%Tier%' OR name LIKE '%Save $15%' OR name LIKE '%Save $50%'"
drupal_db_query "DELETE FROM commerce_promotion WHERE promotion_id NOT IN (SELECT promotion_id FROM commerce_promotion_field_data)"

# Navigate Firefox to the Promotions page to assist the agent
echo "Navigating to Promotions page..."
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/commerce/promotions"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="