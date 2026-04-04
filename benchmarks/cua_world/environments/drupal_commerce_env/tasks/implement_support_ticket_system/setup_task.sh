#!/bin/bash
# Setup script for Support Ticket System task
echo "=== Setting up implement_support_ticket_system ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure services are running
ensure_services_running 120

# 2. Verify dependencies (User janesmith)
echo "Verifying customer user..."
if ! user_exists "janesmith"; then
    echo "Creating user janesmith..."
    cd /var/www/html/drupal
    /var/www/html/drupal/vendor/bin/drush user:create janesmith --mail="jane.smith@example.com" --password="Customer123!"
fi

# 3. Record Initial State (Anti-gaming)
echo "Recording initial state..."
# Max Node ID
INITIAL_MAX_NID=$(drupal_db_query "SELECT MAX(nid) FROM node_field_data" 2>/dev/null)
echo "${INITIAL_MAX_NID:-0}" > /tmp/initial_max_nid

# Existing Content Types
drupal_db_query "SELECT type FROM node_type" > /tmp/initial_node_types.txt

# Existing Views
drupal_db_query "SELECT id FROM views_view" > /tmp/initial_views.txt 2>/dev/null || true
# Backup: check config table if views_view doesn't exist (depends on Drupal version/cache)
drupal_db_query "SELECT name FROM config WHERE name LIKE 'views.view.%'" >> /tmp/initial_views.txt

# Timestamp
date +%s > /tmp/task_start_time.txt

# 4. Prepare Browser
echo "Navigating Firefox..."
# Start at Structure page as it's the entry point for creating types/views
navigate_firefox_to "http://localhost/admin/structure"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Capture Initial Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="