#!/bin/bash
# Setup script for Configure Store Navigation task

echo "=== Setting up Configure Store Navigation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 120

# Ensure Drupal is accessible
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Record baseline state for Menu Links and Blocks
# We use a simple count query here for the baseline
INITIAL_MENU_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM menu_link_content_field_data WHERE menu_name='main'")
echo "${INITIAL_MENU_COUNT:-0}" > /tmp/initial_menu_count

INITIAL_BLOCK_CONTENT_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM block_content_field_data")
echo "${INITIAL_BLOCK_CONTENT_COUNT:-0}" > /tmp/initial_block_content_count

# Navigate Firefox to the Menus admin page to give the agent a helpful starting point
# (Agent still needs to select 'Main navigation', but this puts them in the right area)
echo "Navigating to Structure > Menus..."
navigate_firefox_to "http://localhost/admin/structure/menu"
sleep 5

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="