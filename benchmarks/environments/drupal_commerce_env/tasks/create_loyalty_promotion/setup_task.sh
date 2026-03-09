#!/bin/bash
# Setup script for create_loyalty_promotion task
echo "=== Setting up create_loyalty_promotion ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Fallback for db query if not loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 90

# 1. Clean up any previous attempts (Anti-Gaming/Clean State)
echo "Cleaning up potential conflicting promotions..."
# We search by name to ensure we don't have duplicates
drupal_db_query "DELETE FROM commerce_promotion_field_data WHERE name LIKE '%Loyal Customer Reward%'"
drupal_db_query "DELETE FROM commerce_promotion_field_data WHERE name LIKE '%$20 Off%'"

# 2. Record Initial State
INITIAL_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
echo "${INITIAL_PROMO_COUNT:-0}" > /tmp/initial_promo_count
echo "Initial promotion count: ${INITIAL_PROMO_COUNT:-0}"

# Record task start time
date +%s > /tmp/task_start_timestamp

# 3. Setup Browser
echo "Navigating to Promotions page..."
navigate_firefox_to "http://localhost/admin/commerce/promotions"
sleep 5

# 4. Window Management
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Ensure maximized
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="