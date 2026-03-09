#!/bin/bash
# Setup script for create_promo_landing_view task

echo "=== Setting up Create Promo Landing View Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 90

# Ensure Drupal admin is reachable
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page."
fi

# Clean up any existing view that might conflict (idempotency)
echo "Ensuring no existing view uses path /pro-audio..."
$DRUSH php:eval '
use Drupal\views\Views;
$all_views = Views::getAllViews();
foreach ($all_views as $view) {
    foreach ($view->get("display") as $display) {
        if (isset($display["display_options"]["path"]) && $display["display_options"]["path"] == "pro-audio") {
            echo "Deleting conflicting view: " . $view->id() . "\n";
            $view->delete();
            break;
        }
    }
}
' 2>/dev/null

# Clear caches to ensure clean routing table
$DRUSH cr > /dev/null 2>&1

# Navigate Firefox to the Views listing page to save the agent a step
echo "Navigating to Structure > Views..."
navigate_firefox_to "http://localhost/admin/structure/views"
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
echo "Initial screenshot captured."

echo "=== Setup Complete ==="