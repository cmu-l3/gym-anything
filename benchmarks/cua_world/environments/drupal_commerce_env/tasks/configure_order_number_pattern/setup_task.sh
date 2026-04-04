#!/bin/bash
# Setup script for configure_order_number_pattern task
echo "=== Setting up configure_order_number_pattern ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure all services are running (Drupal, MariaDB, Apache)
echo "Verifying infrastructure services..."
ensure_services_running 90

# Record initial number patterns to identify new ones later
# We use Drush to list config names
echo "Recording initial number patterns..."
cd /var/www/html/drupal
vendor/bin/drush config:list --prefix="commerce_number_pattern.commerce_number_pattern" --format=json > /tmp/initial_patterns.json 2>/dev/null || echo "[]" > /tmp/initial_patterns.json

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Drupal admin page is showing
echo "Ensuring Drupal admin page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to the Commerce Configuration overview to give the agent a good starting point
# We don't go directly to number-patterns to test if they can find it in the menu structure
echo "Navigating to Commerce Configuration..."
navigate_firefox_to "http://localhost/admin/commerce/config"
sleep 5

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="