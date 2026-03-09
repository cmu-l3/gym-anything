#!/bin/bash
# Setup script for Create VIP Products View task

echo "=== Setting up Create VIP Products View Task ==="

source /workspace/scripts/task_utils.sh

# Record initial state to prevent pre-existing data confusion
echo "Recording initial state..."
INITIAL_TERM_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM taxonomy_term_field_data WHERE vid='product_categories'" 2>/dev/null || echo "0")
echo "$INITIAL_TERM_COUNT" > /tmp/initial_term_count

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time

# Ensure services are running
ensure_services_running 90

# Ensure Drupal admin is reachable
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page"
fi

# Navigate to a helpful starting point (Structure page)
echo "Navigating to Structure admin page..."
navigate_firefox_to "http://localhost/admin/structure"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="