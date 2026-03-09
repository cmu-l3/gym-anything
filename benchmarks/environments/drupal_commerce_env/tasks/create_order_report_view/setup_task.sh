#!/bin/bash
echo "=== Setting up Create Order Report View Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 120

# Check if a view with this name already exists and delete it to ensure clean state
# This prevents the agent from just editing a pre-existing view if we re-run
EXISTING_VIEW=$(drush_cmd config:get views.view.order_report 2>/dev/null)
if [ -n "$EXISTING_VIEW" ]; then
    echo "WARNING: cleaning up existing 'order_report' view..."
    drush_cmd config:delete views.view.order_report -y
    drush_cmd cr
fi

# Ensure Drupal admin page is shown
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to Views listing page to start
echo "Navigating to Views list..."
navigate_firefox_to "http://localhost/admin/structure/views"
sleep 5

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="