#!/bin/bash
# Setup script for configure_store_pages task
echo "=== Setting up configure_store_pages ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define local helper for DB queries if not loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 120

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial state
INITIAL_NODE_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM node_field_data")
echo "${INITIAL_NODE_COUNT:-0}" > /tmp/initial_node_count.txt

INITIAL_MENU_LINK_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM menu_link_content_data")
echo "${INITIAL_MENU_LINK_COUNT:-0}" > /tmp/initial_menu_link_count.txt

# Record initial site config to ensure we detect changes
cd /var/www/html/drupal
INITIAL_SITE_NAME=$(vendor/bin/drush config:get system.site name --format=string 2>/dev/null || echo "Drupal")
echo "$INITIAL_SITE_NAME" > /tmp/initial_site_name.txt

# Ensure Firefox is open and logged in
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to Basic Site Settings as a helpful starting point
# This puts the agent in the right general area for step 1
navigate_firefox_to "http://localhost/admin/config/system/site-information"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="