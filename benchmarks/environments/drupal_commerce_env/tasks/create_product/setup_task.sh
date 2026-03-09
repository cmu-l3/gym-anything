#!/bin/bash
# Setup script for Create Product task (pre_task hook)
# Ensures Drupal Commerce admin is showing Products page

echo "=== Setting up Create Product Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial product count for verification
echo "Recording initial product count..."
INITIAL_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_product_count
chmod 666 /tmp/initial_product_count
echo "Initial product count: $INITIAL_COUNT"

# Ensure all services (Docker, MariaDB, Apache, Firefox) are running
# This handles cases where post_start hook timed out or failed
echo "Verifying infrastructure services..."
ensure_services_running 90

# Ensure Drupal admin page is showing (not blank Firefox tab)
echo "Ensuring Drupal admin page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
    echo "Attempting direct navigation..."
fi
echo "Drupal admin page setup attempted"

# Navigate to the Products admin page
echo "Navigating to Commerce > Products..."
navigate_firefox_to "http://localhost/admin/commerce/products"
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
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved - verify it shows Drupal Commerce Products page"

echo "=== Create Product Task Setup Complete ==="
echo "Agent should be on the Drupal Commerce Products admin page (already logged in)."
