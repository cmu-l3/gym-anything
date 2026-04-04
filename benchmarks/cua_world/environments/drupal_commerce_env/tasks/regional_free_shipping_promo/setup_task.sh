#!/bin/bash
# Setup script for Regional Free Shipping Promotion task
echo "=== Setting up Regional Free Shipping Promotion Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Fallback for database query if utils not fully loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 90

# Record initial promotion count
INITIAL_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
echo "${INITIAL_COUNT:-0}" > /tmp/initial_promo_count

# Clean up any existing promotion with this name to ensure a clean start
# This prevents the agent from seeing a completed task or verification confusion
EXISTING_ID=$(drupal_db_query "SELECT promotion_id FROM commerce_promotion_field_data WHERE name = 'California Pilot' LIMIT 1")
if [ -n "$EXISTING_ID" ]; then
    echo "Cleaning up existing 'California Pilot' promotion (ID: $EXISTING_ID)..."
    # Delete from main table
    drupal_db_query "DELETE FROM commerce_promotion_field_data WHERE promotion_id = $EXISTING_ID"
    drupal_db_query "DELETE FROM commerce_promotion WHERE promotion_id = $EXISTING_ID"
    # Clean up related tables (conditions, stores, etc) - simplifed cleanup
    drupal_db_query "DELETE FROM commerce_promotion__conditions WHERE entity_id = $EXISTING_ID"
    drupal_db_query "DELETE FROM commerce_promotion__stores WHERE entity_id = $EXISTING_ID"
fi

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure Drupal admin page is showing
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to the Promotions admin page to save the agent a step
echo "Navigating to Commerce > Promotions..."
navigate_firefox_to "http://localhost/admin/commerce/promotions"
sleep 5

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="