#!/bin/bash
# Setup script for Add Gift Order Fields task
# Ensures Drupal Commerce is ready and navigates to the Order Types configuration

echo "=== Setting up Add Gift Order Fields Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure all services are running
echo "Verifying infrastructure services..."
ensure_services_running 90

# Ensure Drupal admin page is showing
echo "Ensuring Drupal admin page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Clean up any previous attempts (idempotency)
# We remove the fields if they already exist so the agent starts fresh
echo "Cleaning up any existing gift fields..."
cd "$DRUPAL_DIR"
$DRUSH field:delete commerce_order.default.field_gift_message -y 2>/dev/null || true
$DRUSH field:delete commerce_order.default.field_gift_wrap -y 2>/dev/null || true
# Also clean storage if the field instance is gone but storage remains
$DRUSH config:delete field.storage.commerce_order.field_gift_message -y 2>/dev/null || true
$DRUSH config:delete field.storage.commerce_order.field_gift_wrap -y 2>/dev/null || true
$DRUSH cr

# Navigate to the Order Types > Default > Manage Fields page
# This puts the agent exactly where they need to be to start
TARGET_URL="http://localhost/admin/commerce/config/order-types/default/edit/fields"
echo "Navigating to $TARGET_URL..."
navigate_firefox_to "$TARGET_URL"
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

echo "=== Setup Complete ==="