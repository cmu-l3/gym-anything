#!/bin/bash
# Setup script for implement_brand_classification task

echo "=== Setting up Implement Brand Classification Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
echo "Verifying infrastructure services..."
ensure_services_running 90

# Ensure Drupal admin page is showing
echo "Ensuring Drupal admin page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to the Commerce Configuration page as a starting point
echo "Navigating to Commerce Configuration..."
navigate_firefox_to "http://localhost/admin/commerce/config"
sleep 5

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="