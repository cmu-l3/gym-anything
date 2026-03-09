#!/bin/bash
# Setup script for Create Store Blog task
echo "=== Setting up Create Store Blog Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define fallback for db query if not present in environment yet
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 120

# Record initial state to detect changes
echo "Recording initial state..."

# Count content types
INITIAL_TYPE_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'node.type.%'")
echo "${INITIAL_TYPE_COUNT:-0}" > /tmp/initial_type_count

# Count vocabularies
INITIAL_VOCAB_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'taxonomy.vocabulary.%'")
echo "${INITIAL_VOCAB_COUNT:-0}" > /tmp/initial_vocab_count

# Count nodes
INITIAL_NODE_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM node_field_data")
echo "${INITIAL_NODE_COUNT:-0}" > /tmp/initial_node_count

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure we are logged in and on the admin structure page
echo "Navigating to Structure admin page..."
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/structure"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="