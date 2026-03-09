#!/bin/bash
# Setup script for implement_curated_cross_sells
echo "=== Setting up implement_curated_cross_sells ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 120

# Ensure Drupal admin is reachable
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate Firefox to the Commerce Configuration page to give a helpful starting point
# or just the main Commerce dashboard.
echo "Navigating to Commerce Dashboard..."
navigate_firefox_to "http://localhost/admin/commerce"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Clean up any previous attempts (if re-running in same env)
# This removes the field configuration if it exists to ensure a clean start
echo "Ensuring clean state..."
if [ -f "$DRUPAL_DIR/vendor/bin/drush" ]; then
    cd "$DRUPAL_DIR"
    # Check if field exists
    if $DRUSH config:get field.storage.commerce_product.field_related_accessories > /dev/null 2>&1; then
        echo "Cleaning up previous field_related_accessories..."
        $DRUSH field:delete field_related_accessories --bundle=default --entity_type=commerce_product -y > /dev/null 2>&1 || true
        $DRUSH cr > /dev/null 2>&1 || true
    fi
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="