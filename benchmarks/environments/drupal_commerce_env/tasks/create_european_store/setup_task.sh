#!/bin/bash
# Setup script for Create European Store task
echo "=== Setting up Create European Store Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definition if utils not loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 120

# Record initial store count and max ID to verify new creation
INITIAL_STORE_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_store_field_data")
INITIAL_STORE_COUNT=${INITIAL_STORE_COUNT:-0}
MAX_STORE_ID=$(drupal_db_query "SELECT MAX(store_id) FROM commerce_store_field_data")
MAX_STORE_ID=${MAX_STORE_ID:-0}

echo "$INITIAL_STORE_COUNT" > /tmp/initial_store_count
echo "$MAX_STORE_ID" > /tmp/max_store_id

echo "Initial store count: $INITIAL_STORE_COUNT"
echo "Max store ID: $MAX_STORE_ID"

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open and navigate to Stores configuration
# This saves the agent some navigation time but leaves the actual work to them
echo "Navigating to Stores configuration..."
navigate_firefox_to "http://localhost/admin/commerce/config/stores"
sleep 5

# Focus and maximize window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="