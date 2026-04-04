#!/bin/bash
# Setup script for implement_inventory_tracking task
set -e
echo "=== Setting up Inventory Tracking Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 120

# cleanup function to ensure clean state
cleanup_previous_state() {
    echo "Ensuring clean state..."
    cd "$DRUPAL_DIR"
    
    # 1. Delete view if exists
    if $DRUSH config:status "views.view.low_stock_report" >/dev/null 2>&1; then
        echo "Deleting existing view..."
        $DRUSH config:delete "views.view.low_stock_report" -y 2>/dev/null || true
    fi

    # 2. Delete field if exists
    # We need to delete the field instance and storage
    if $DRUSH config:status "field.field.commerce_product_variation.default.field_stock_level" >/dev/null 2>&1; then
        echo "Deleting existing field instance..."
        $DRUSH config:delete "field.field.commerce_product_variation.default.field_stock_level" -y 2>/dev/null || true
    fi
    if $DRUSH config:status "field.storage.commerce_product_variation.field_stock_level" >/dev/null 2>&1; then
        echo "Deleting existing field storage..."
        $DRUSH config:delete "field.storage.commerce_product_variation.field_stock_level" -y 2>/dev/null || true
    fi
    
    # Clear cache to apply deletions
    $DRUSH cr >/dev/null 2>&1
}

cleanup_previous_state

# Ensure Firefox is ready
if ! ensure_drupal_shown 60; then
    echo "WARNING: Firefox not detected, restarting..."
    pkill -f firefox || true
    su - ga -c "DISPLAY=:1 firefox http://localhost/admin/commerce/config/product-variation-types/default/edit/fields &"
fi

# Navigate to the Variation Types Field UI (helpful starting point)
navigate_firefox_to "http://localhost/admin/commerce/config/product-variation-types/default/edit/fields"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="